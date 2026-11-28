import { describe, expect, it } from 'vitest';
import { sanitizePartyImageUrl } from './invite';
import { memberOf, trackOf } from './models';

describe('party image URL safety', () => {
  it('keeps ordinary public HTTP(S) artwork and CDN images', () => {
    expect(sanitizePartyImageUrl('https://i.ytimg.com/vi/abc/hqdefault.jpg'))
      .toBe('https://i.ytimg.com/vi/abc/hqdefault.jpg');
    expect(sanitizePartyImageUrl('http://cdn.example.net/cover.png'))
      .toBe('http://cdn.example.net/cover.png');
    expect(sanitizePartyImageUrl('https://[2606:4700:4700::1111]/avatar.png'))
      .toBe('https://[2606:4700:4700::1111]/avatar.png');
  });

  it('rejects local, private, special-use and malformed image URLs', () => {
    for (const value of [
      null,
      '',
      'javascript:alert(1)',
      'data:image/png;base64,AAAA',
      'file:///etc/passwd',
      'https://user:pass@example.com/avatar.png',
      'https://localhost/avatar.png',
      'https://printer.local/avatar.png',
      'https://host.home.arpa/avatar.png',
      'https://127.0.0.1/avatar.png',
      'https://127.1/avatar.png',
      'https://0x7f000001/avatar.png',
      'https://10.0.0.1/avatar.png',
      'https://169.254.169.254/latest/meta-data/',
      'https://192.168.1.2/avatar.png',
      'https://[::1]/avatar.png',
      'https://[::ffff:192.168.1.2]/avatar.png',
      'https://[fc00::1]/avatar.png',
      'https://[fe80::1]/avatar.png',
      'https://[fec0::1]/avatar.png',
      'https://[ff02::1]/avatar.png',
      'https://[2001:db8::1]/avatar.png',
      'https://example.com:99999/avatar.png',
      `https://example.com/${'x'.repeat(4_100)}`,
    ]) {
      expect(sanitizePartyImageUrl(value)).toBeNull();
    }
  });

  it('drops unsafe avatar and thumbnail URLs when decoding old/custom server payloads', () => {
    expect(memberOf({
      memberId: 'member-1',
      avatarUrl: 'https://192.168.1.1/private.png',
    }).avatarUrl).toBeNull();
    expect(trackOf({
      videoId: 'abcdefghijk',
      thumbnailUrl: 'javascript:alert(1)',
    }).thumbnailUrl).toBeNull();
  });
});
