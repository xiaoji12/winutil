// Shared external links, so astro.config.mjs and Header.astro can't drift out of sync.
export const siteLinks = {
	store: { label: '商店', href: 'https://christitus.com/downloads/' },
	forums: { label: '论坛', href: 'https://forum.christitus.com/' },
} as const;
