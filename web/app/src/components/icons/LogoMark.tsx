import markSvg from '@/assets/logo-mark.svg?raw';

// MusikKu's music-note mark; currentColor lets it follow the surrounding text colour.
const markup = markSvg.replace(/width="\d+" height="\d+"/, 'width="100%" height="100%"');

export function LogoMark({ size = 20, className }: { size?: number; className?: string }) {
  return (
    <span
      aria-hidden="true"
      className={className}
      style={{ display: 'inline-flex', width: size, height: size }}
      dangerouslySetInnerHTML={{ __html: markup }}
    />
  );
}
