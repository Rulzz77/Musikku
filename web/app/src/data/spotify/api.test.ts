import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SpotifyTrack } from '@bitchord/shared/bridge';
import type { Track } from '@/data/music/types';

const mocks = vi.hoisted(() => {
  class PartialSearchError extends Error {
    constructor(readonly candidates: unknown[], cause: unknown, readonly artistIds: string[] = []) {
      super(`YouTube Music search was incomplete: ${String(cause)}`);
      this.name = 'SearchSongsIncompleteError';
    }
  }
  return { searchSpotifySongs: vi.fn(), fetchArtist: vi.fn(), SearchSongsIncompleteError: PartialSearchError };
});
vi.mock('@/data/music/api', () => ({
  searchSpotifySongs: mocks.searchSpotifySongs,
  fetchArtist: mocks.fetchArtist,
  SearchSongsIncompleteError: mocks.SearchSongsIncompleteError,
}));

import { SearchSongsIncompleteError } from '@/data/music/api';
import { clearCachedSpotifyMatch, matchToYouTube, nextSpotifyPageOffset } from './api';

function spotifyTrack(overrides: Partial<SpotifyTrack> = {}): SpotifyTrack {
  return {
    id: 'spotify-track-test',
    title: 'Dumes',
    artist: 'Guyon Waton',
    leadArtist: 'Guyon Waton',
    album: 'Album',
    durationMs: 210_000,
    imageUrl: null,
    ...overrides,
  };
}

function youtubeTrack(videoId: string, title: string, artist: string): Track {
  return {
    videoId,
    title,
    artists: [{ name: artist, id: null }],
    album: { name: 'Album', id: null },
    durationSec: 210,
    explicit: false,
    thumbnail: null,
    index: null,
    plays: null,
  };
}

describe('Spotify import safety', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it('does not import the first YouTube result when its title is only a longer substring match', async () => {
    const wrong = youtubeTrack('wrong-longer-title', 'Dumes Bersama', 'Guyon Waton');
    mocks.searchSpotifySongs.mockResolvedValue({ tracks: [wrong], artistIds: [] });

    await expect(matchToYouTube(spotifyTrack())).resolves.toBeNull();
  });

  it('does not import a same-title result credited only to a different singer', async () => {
    const cover = youtubeTrack('wrong-singer', 'Dumes', 'Different Singer');
    mocks.searchSpotifySongs.mockResolvedValue({ tracks: [cover], artistIds: [] });

    await expect(matchToYouTube(spotifyTrack())).resolves.toBeNull();
  });

  it('searches the original Spotify title and lead artist before normalized terms', async () => {
    const correct = youtubeTrack('tanpo-correct', 'Tanpo Tresnamu', 'Denny Caknan');
    mocks.searchSpotifySongs.mockImplementation(async (query: string) => ({
      tracks: query === 'Tanpo Tresnamu (Official Audio) Denny Caknan' ? [correct] : [],
      artistIds: [],
    }));

    await expect(matchToYouTube(spotifyTrack({
      id: 'spotify-tanpo',
      title: 'Tanpo Tresnamu (Official Audio)',
      artist: 'Denny Caknan',
      leadArtist: 'Denny Caknan',
    }))).resolves.toMatchObject({ videoId: 'tanpo-correct' });
    expect(mocks.searchSpotifySongs).toHaveBeenCalledTimes(1);
    expect(mocks.searchSpotifySongs).toHaveBeenCalledWith('Tanpo Tresnamu (Official Audio) Denny Caknan', ['Denny Caknan']);
  });

  it('searches individual structured Spotify credits and accepts a strict composite artist alias', async () => {
    const alias = { ...youtubeTrack('friska-gasentra', 'Budak Saha', 'Friska Gasentra'), durationSec: 287 };
    mocks.searchSpotifySongs.mockImplementation(async (query: string) => ({
      tracks: query === 'Budak Saha Friska' ? [alias] : [],
      artistIds: [],
    }));

    await expect(matchToYouTube(spotifyTrack({
      id: 'spotify-budak-saha',
      title: 'Budak Saha',
      artist: 'Gasentra Pajampangan, Friska',
      leadArtist: 'Gasentra Pajampangan',
      artistCredits: ['Gasentra Pajampangan', 'Friska'],
      durationMs: 287_000,
    }))).resolves.toMatchObject({ videoId: 'friska-gasentra' });
    expect(mocks.searchSpotifySongs).toHaveBeenCalledWith('Budak Saha Friska', ['Gasentra Pajampangan', 'Friska']);
  });

  it('matches an exact structured secondary Spotify credit at the same runtime', async () => {
    const secondary = { ...youtubeTrack('secondary-credit-only', 'Budak Saha', 'Friska'), durationSec: 287 };
    mocks.searchSpotifySongs.mockImplementation(async (query: string) => ({
      tracks: query === 'Budak Saha Friska' ? [secondary] : [],
      artistIds: [],
    }));
    await expect(matchToYouTube(spotifyTrack({
      id: 'spotify-secondary-credit',
      title: 'Budak Saha',
      artist: 'Gasentra Pajampangan, Friska',
      leadArtist: 'Gasentra Pajampangan',
      artistCredits: ['Gasentra Pajampangan', 'Friska'],
      durationMs: 287_000,
    }))).resolves.toMatchObject({ videoId: 'secondary-credit-only' });
    expect(mocks.searchSpotifySongs).toHaveBeenCalledWith('Budak Saha Friska', ['Gasentra Pajampangan', 'Friska']);
  });

  it('falls back to the matching Spotify artist page when global Search misses', async () => {
    const artistSong = youtubeTrack('artist-top-song', 'Dumes', 'Guyon Waton');
    mocks.searchSpotifySongs.mockResolvedValue({ tracks: [], artistIds: ['UCguyon'] });
    mocks.fetchArtist.mockResolvedValue({
      topSongs: [artistSong],
    });
    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-artist-fallback' }))).resolves.toMatchObject({
      videoId: 'artist-top-song',
    });
    expect(mocks.fetchArtist).toHaveBeenCalledWith('UCguyon');
  });

  it('accepts a verified title, primary artist and runtime match', async () => {
    const correct = youtubeTrack('correct-song', 'Dumes', 'Guyon Waton');
    mocks.searchSpotifySongs.mockResolvedValue({ tracks: [correct], artistIds: [] });

    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-correct' }))).resolves.toMatchObject({
      videoId: 'correct-song',
    });
  });

  it('uses visible first-page results when a later Songs page fails', async () => {
    const correct = youtubeTrack('partial-visible-match', 'Dumes', 'Guyon Waton');
    mocks.searchSpotifySongs.mockRejectedValue(new SearchSongsIncompleteError(
      [correct],
      new Error('continuation unavailable'),
      [],
    ));

    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-partial-page' }))).resolves.toMatchObject({
      videoId: 'partial-visible-match',
    });
  });

  it('does not turn a failed search request into an unmatched song', async () => {
    mocks.searchSpotifySongs.mockRejectedValue(new Error('temporary YouTube search failure'));

    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-retry' }))).rejects.toThrow(
      'temporary YouTube search failure',
    );
  });

  it('can retry a previous no-match after clearing the cached result', async () => {
    const track = spotifyTrack({ id: 'spotify-no-match-retry' });
    mocks.searchSpotifySongs.mockResolvedValue({ tracks: [], artistIds: [] });
    await expect(matchToYouTube(track)).resolves.toBeNull();

    const correct = youtubeTrack('retry-correct-song', 'Dumes', 'Guyon Waton');
    mocks.searchSpotifySongs.mockResolvedValue({ tracks: [correct], artistIds: [] });
    await expect(matchToYouTube(track)).resolves.toBeNull();

    clearCachedSpotifyMatch(track.id);
    await expect(matchToYouTube(track)).resolves.toMatchObject({ videoId: 'retry-correct-song' });
  });

  it('rejects a zero-sized page before Spotify reports the playlist complete', () => {
    expect(nextSpotifyPageOffset(0, 250, 100)).toBe(100);
    expect(nextSpotifyPageOffset(100, 250, 100)).toBe(200);
    expect(nextSpotifyPageOffset(200, 250, 50)).toBeNull();
    expect(() => nextSpotifyPageOffset(100, 250, 0)).toThrow('stopped at 100 of 250');
    expect(() => nextSpotifyPageOffset(0, 50, 100)).toThrow('reports 50');
  });
});
