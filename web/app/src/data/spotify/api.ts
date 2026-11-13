import type { SpotifyPlaylist, SpotifyTrack } from '@bitchord/shared/bridge';
import { best, primaryArtist, queries, type MatchCandidate, type MatchTarget } from '@/data/match/trackMatcher';
import { searchSongs } from '@/data/music/api';
import type { Track } from '@/data/music/types';
import { getBridge } from '@/extension/bridge';

/**
 * Spotify through the extension (prompt §7.1): the library, a playlist's
 * tracks, and matching each one to its YouTube Music song. Ports
 * SpotifyLibrary.kt's paging and SpotifyImporter.matchTrack.
 */

export const LIKED_ID = 'liked';

function bridge() {
  const b = getBridge();
  if (!b) throw new Error('The BitChord extension is not installed');
  return b;
}

/**
 * Move through the raw Spotify page size, not only its parsed track count.
 * A zero-sized page before the advertised total means the playlist is partial.
 */
export function nextSpotifyPageOffset(offset: number, total: number, raw: number): number | null {
  if (!Number.isInteger(offset) || !Number.isInteger(total) || !Number.isInteger(raw) || offset < 0 || total < 0 || raw < 0) {
    throw new Error('Spotify returned invalid pagination metadata');
  }
  if (raw === 0) {
    if (offset < total) throw new Error(`Spotify pagination stopped at ${offset} of ${total} entries`);
    return null;
  }
  const next = offset + raw;
  if (next <= offset) throw new Error('Spotify pagination did not advance');
  return next < total ? next : null;
}

/** Every playlist in the library, Liked Songs first, however many pages it takes. */
export async function fetchSpotifyPlaylists(): Promise<SpotifyPlaylist[]> {
  const out: SpotifyPlaylist[] = [];
  for (let offset = 0; ; ) {
    const page = await bridge().call('spotify.playlists', { offset }, { timeoutMs: 30_000 });
    out.push(...page.items);
    const next = nextSpotifyPageOffset(offset, page.total, page.raw);
    if (next === null) break;
    offset = next;
  }
  return out;
}

export function fetchSpotifyPlaylistInfo(playlistId: string) {
  return bridge().call('spotify.playlist', { playlistId }, { timeoutMs: 30_000 });
}

/** Every track of a playlist; [onPage] gets the running list after each page, so a long one fills in. */
export async function fetchSpotifyTracks(playlistId: string, onPage: (soFar: SpotifyTrack[], total: number) => void): Promise<SpotifyTrack[]> {
  const out: SpotifyTrack[] = [];
  for (let offset = 0; ; ) {
    const page = await bridge().call('spotify.tracks', { playlistId, offset }, { timeoutMs: 30_000 });
    out.push(...page.items);
    onPage([...out], page.total);
    const next = nextSpotifyPageOffset(offset, page.total, page.raw);
    if (next === null) break;
    offset = next;
  }
  return out;
}

/** A Spotify row as a list row, before its YouTube Music version is known. */
export function pendingTrack(track: SpotifyTrack, unavailable: 'matching' | 'missing' = 'matching'): Track {
  return {
    videoId: `spotify:${track.id}`,
    title: track.title,
    artists: track.artist ? track.artist.split(', ').map((name) => ({ name, id: null })) : [],
    album: track.album ? { name: track.album, id: null } : null,
    durationSec: track.durationMs > 0 ? Math.round(track.durationMs / 1000) : null,
    explicit: false,
    thumbnail: track.imageUrl,
    index: null,
    plays: null,
    unavailable,
  };
}

export function candidateOf(track: Track): MatchCandidate {
  return {
    title: track.title,
    artist: track.artists.map((a) => a.name).join(', '),
    durationSec: track.durationSec,
    album: track.album?.name ?? null,
    explicit: track.explicit,
  };
}

const matched = new Map<string, Track | null>();

/**
 * The YouTube Music counterpart of a Spotify row, or null when no result
 * passes the same title/version/lead-artist checks used by Android.
 *
 * Search several normalized queries, accumulate candidates, and never take
 * the first search row as a fallback. A cover or unrelated remix is safer as
 * an unmatched row than as a silently incorrect import.
 */
export async function matchToYouTube(track: SpotifyTrack): Promise<Track | null> {
  if (matched.has(track.id)) return matched.get(track.id)!;

  const leadArtist = track.leadArtist?.trim() || primaryArtist(track.artist);
  const target: MatchTarget = {
    title: track.title,
    artist: track.artist,
    requiredArtistName: leadArtist || null,
    requireSharedArtist: !!track.artist.trim(),
    requireExactTitle: true,
    durationSec: track.durationMs > 0 ? Math.round(track.durationMs / 1000) : null,
    album: track.album,
  };
  const baseQueries = queries(target);
  const albumQuery = track.album?.trim() && baseQueries[0] ? `${baseQueries[0]} ${track.album.trim()}` : null;
  const searchTerms = [...new Set([...baseQueries, ...(albumQuery ? [albumQuery] : [])])];
  const candidates = new Map<string, Track>();
  let searchFailure: unknown = null;

  for (const query of searchTerms) {
    try {
      const rows = await searchSongs(query);
      for (const row of rows) {
        if (row.videoId?.trim()) candidates.set(row.videoId, row);
      }
    } catch (error) {
      searchFailure ??= error;
    }
  }

  const scored = best([...candidates.values()].map((candidate) => ({ ...candidateOf(candidate), track: candidate })), target);
  if (!scored && searchFailure) throw searchFailure;
  const found = scored?.track ?? null;
  const result = found ? { ...found, thumbnail: found.thumbnail ?? track.imageUrl } : null;
  matched.set(track.id, result);
  return result;
}

// ---- Canvas (SpotifyCanvas / DesktopSpotifyCanvas) ---------------------------------

const canvases = new Map<string, string | null>();

/**
 * The looping clip Spotify shows behind [track], or null. The Spotify
 * counterpart is found with the same matcher, so a cover or a remix never
 * lends its canvas to the original.
 */
export async function fetchCanvas(track: { videoId: string; title: string; artist: string; durationSec: number }): Promise<string | null> {
  if (canvases.has(track.videoId)) return canvases.get(track.videoId)!;
  const hits = await bridge().call('spotify.searchTracks', { query: `${track.title} ${track.artist}` }, { timeoutMs: 20_000 });
  const pick = best(
    hits.map((h) => ({
      title: h.title,
      artist: h.artist,
      durationSec: h.durationMs > 0 ? Math.round(h.durationMs / 1000) : null,
      album: h.album,
      id: h.id,
    })),
    { title: track.title, artist: track.artist, durationSec: track.durationSec > 0 ? Math.round(track.durationSec) : null },
  );
  const url = pick ? (await bridge().call('spotify.canvas', { trackId: pick.id }, { timeoutMs: 20_000 })).url : null;
  canvases.set(track.videoId, url);
  if (canvases.size > 200) canvases.delete(canvases.keys().next().value!);
  return url;
}
