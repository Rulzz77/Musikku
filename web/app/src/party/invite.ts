/**
 * Party invites (JamInviteLink.kt): `https://bitchord.kushagrasingh.in/invite/<CODE>`,
 * optionally `?server=<custom server>`, and `bitchord://party/<CODE>`. On the
 * web the first is a route of this app (`/invite/:code`).
 */

export const INVITE_ORIGIN = 'https://bitchord.kushagrasingh.in';
export const CODE_LENGTH = 6;

/** Letters and digits only, upper case; null unless it's six of them. */
export function cleanCode(raw: string): string | null {
  const cleaned = raw.replace(/[^A-Za-z0-9]/g, '').toUpperCase();
  return cleaned.length === CODE_LENGTH ? cleaned : null;
}

function isLocalDevelopmentHost(hostname: string): boolean {
  const host = hostname.toLowerCase().replace(/^\[|\]$/g, '');
  return host === 'localhost' || host.endsWith('.localhost') ||
    host === '127.0.0.1' || host === '::1';
}

export function sanitizeServerUrl(raw: string | null | undefined): string | null {
  const trimmed = raw?.trim().replace(/\/+$/, '');
  if (!trimmed) return null;
  const withScheme = /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`;
  try {
    const parsed = new URL(withScheme);
    if (!parsed.hostname || parsed.username || parsed.password || parsed.search || parsed.hash) return null;
    // Production party servers must use TLS. Plain HTTP is only accepted for
    // local development servers where TLS is commonly unavailable.
    if (parsed.protocol !== 'https:' &&
        !(parsed.protocol === 'http:' && isLocalDevelopmentHost(parsed.hostname))) return null;
    return `${parsed.protocol}//${parsed.host}${parsed.pathname.replace(/\\/+$/, '')}`;
  } catch {
    return null;
  }
}

export function parseInvite(value: string): { code: string; serverUrl: string | null } | null {
  let url: URL;
  try {
    url = new URL(value);
  } catch {
    return null;
  }
  const rawServer = url.searchParams.get('server');
  const server = sanitizeServerUrl(rawServer);
  if (rawServer && !server) return null;
  if (url.protocol === 'bitchord:' && url.host.toLowerCase() === 'party') {
    const code = cleanCode(url.pathname.replace(/^\/+|\/+$/g, '') || url.searchParams.get('code') || '');
    return code ? { code, serverUrl: server } : null;
  }
  const match = url.pathname.match(/^\/invite\/([A-Za-z0-9]{6})$/);
  const secureInvitePage = url.protocol === 'https:' ||
    (url.protocol === 'http:' && isLocalDevelopmentHost(url.hostname));
  if (secureInvitePage && match) return { code: match[1]!.toUpperCase(), serverUrl: server };
  return null;
}

/** The link to share (JamInviteLink.url): a custom server's own invite page, else the public site's. */
export function inviteUrl(code: string, customServer: string | null): string {
  const base = sanitizeServerUrl(customServer);
  const origin = base && base.toLowerCase() !== INVITE_ORIGIN ? base : INVITE_ORIGIN;
  return `${origin}/invite/${code.toUpperCase()}`;
}
