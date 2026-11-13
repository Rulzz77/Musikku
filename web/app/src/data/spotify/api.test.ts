import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SpotifyTrack } from '@bitchord/shared/bridge';
import type { Track } from '@/data/music/types';

const mocks = vi.hoisted(() => {
  class PartialSearchError extends Error {
    constructor(readonly candidates: unknown[], cause: unknown) {
      super(`YouTube Music search was incomplete: ${String(cause)}`);
      this.name = 'SearchSongsIncompleteError';
    }
  }
  return { searchSongs: vi.fn(), SearchSongsIncompleteError: PartialSearchError };
});
vi.mock('@/data/music/api', () => ({
  searchSongs: mocks.searchSongs,
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
    mocks.searchSongs.mockResolvedValue([wrong]);

    await expect(matchToYouTube(spotifyTrack())).resolves.toBeNull();
  });

  it('does not import a same-title result credited only to a different singer', async () => {
    const cover = youtubeTrack('wrong-singer', 'Dumes', 'Different Singer');
    mocks.searchSongs.mockResolvedValue([cover]);

    await expect(matchToYouTube(spotifyTrack())).resolves.toBeNull();
  });

  it('searches the original Spotify title and lead artist before normalized terms', async () => {
    const correct = youtubeTrack('tanpo-correct', 'Tanpo Tresnamu', 'Denny Caknan');
    mocks.searchSongs.mockImplementation(async (query: string) =>
      query === 'Tanpo Tresnamu (Official Audio) Denny Caknan' ? [correct] : [],
    );

    await expect(matchToYouTube(spotifyTrack({
      id: 'spotify-tanpo',
      title: 'Tanpo Tresnamu (Official Audio)',
      artist: 'Denny Caknan',
      leadArtist: 'Denny Caknan',
    }))).resolves.toMatchObject({ videoId: 'tanpo-correct' });
    expect(mocks.searchSongs).toHaveBeenCalledTimes(1);
    expect(mocks.searchSongs).toHaveBeenCalledWith('Tanpo Tresnamu (Official Audio) Denny Caknan');
  });

  it('searches individual structured Spotify credits and accepts a strict composite artist alias', async () => {
    const alias = youtubeTrack('friska-gasentra', 'Budak Saha', 'Friska Gasentra');
    mocks.searchSongs.mockImplementation(async (query: string) =>
      query === 'Budak Saha Friska' ? [alias] : [],
    );

    await expect(matchToYouTube(spotifyTrack({
      id: 'spotify-budak-saha',
      title: 'Budak Saha',
      artist: 'Gasentra Pajampangan, Friska',
      leadArtist: 'Gasentra Pajampangan',
      artistCredits: ['Gasentra Pajampangan', 'Friska'],
      durationMs: 287_000,
    }))).resolves.toMatchObject({ videoId: 'friska-gasentra' });
    expect(mocks.searchSongs).toHaveBeenCalledWith('Budak Saha Friska');
  });

  it('accepts a verified title, primary artist and runtime match', async () => {
    const correct = youtubeTrack('correct-song', 'Dumes', 'Guyon Waton');
    mocks.searchSongs.mockResolvedValue([correct]);

    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-correct' }))).resolves.toMatchObject({
      videoId: 'correct-song',
    });
  });

  it('uses visible first-page results when a later Songs page fails', async () => {
    const correct = youtubeTrack('partial-visible-match', 'Dumes', 'Guyon Waton');
    mocks.searchSongs.mockRejectedValue(new SearchSongsIncompleteError(
      [correct],
      new Error('continuation unavailable'),
    ));

    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-partial-page' }))).resolves.toMatchObject({
      videoId: 'partial-visible-match',
    });
  });

  it('does not turn a failed search request into an unmatched song', async () => {
    mocks.searchSongs.mockRejectedValue(new Error('temporary YouTube search failure'));

    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-retry' }))).rejects.toThrow(
      'temporary YouTube search failure',
    );
  });

  it('can retry a previous no-match after clearing the cached result', async () => {
    const track = spotifyTrack({ id: 'spotify-no-match-retry' });
    mocks.searchSongs.mockResolvedValue([]);
    await expect(matchToYouTube(track)).resolves.toBeNull();

    const correct = youtubeTrack('retry-correct-song', 'Dumes', 'Guyon Waton');
    mocks.searchSongs.mockResolvedValue([correct]);
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
