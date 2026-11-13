import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { SpotifyTrack } from '@bitchord/shared/bridge';
import type { Track } from '@/data/music/types';

const mocks = vi.hoisted(() => ({ searchSongs: vi.fn() }));
vi.mock('@/data/music/api', () => ({ searchSongs: mocks.searchSongs }));

import { matchToYouTube, nextSpotifyPageOffset } from './api';

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

  it('accepts a verified title, primary artist and runtime match', async () => {
    const correct = youtubeTrack('correct-song', 'Dumes', 'Guyon Waton');
    mocks.searchSongs.mockResolvedValue([correct]);

    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-correct' }))).resolves.toMatchObject({
      videoId: 'correct-song',
    });
  });

  it('does not turn a failed search request into an unmatched song', async () => {
    mocks.searchSongs.mockRejectedValue(new Error('temporary YouTube search failure'));

    await expect(matchToYouTube(spotifyTrack({ id: 'spotify-retry' }))).rejects.toThrow(
      'temporary YouTube search failure',
    );
  });

  it('rejects a zero-sized page before Spotify reports the playlist complete', () => {
    expect(nextSpotifyPageOffset(0, 250, 100)).toBe(100);
    expect(nextSpotifyPageOffset(100, 250, 100)).toBe(200);
    expect(nextSpotifyPageOffset(200, 250, 100)).toBeNull();
    expect(() => nextSpotifyPageOffset(100, 250, 0)).toThrow('stopped at 100 of 250');
  });
});
