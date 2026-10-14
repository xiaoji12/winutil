// @ts-check
import { defineConfig } from 'astro/config';
import starlight from '@astrojs/starlight';
import { siteLinks } from './src/site-links.ts';

// https://astro.build/config
export default defineConfig({
	site: 'https://winutil.christitus.com/',
	integrations: [
		starlight({
			title: 'WinUtil',
			description: "Chris Titus Tech 出品的 Windows 实用工具——安装应用、应用优化项、执行修复，在一处完成对 Windows 的管理。",
			logo: {
				src: './src/assets/branding/navlogo.png',
				replacesTitle: true,
			},
			favicon: '/favicon.svg',
			head: [
				{ tag: 'meta', attrs: { property: 'og:image', content: 'https://winutil.christitus.com/social-preview.png' } },
				{ tag: 'meta', attrs: { property: 'og:image:width', content: '1200' } },
				{ tag: 'meta', attrs: { property: 'og:image:height', content: '630' } },
				{ tag: 'meta', attrs: { name: 'twitter:image', content: 'https://winutil.christitus.com/social-preview.png' } },
			],
			social: [
				{ icon: 'github', label: 'GitHub', href: 'https://github.com/ChrisTitusTech/winutil' },
				{ icon: 'discord', label: 'Discord', href: 'https://discord.gg/RUbZUZyByQ' },
			],
			// Global theme overrides (colors, fonts, landing-page section styles).
			customCss: ['./src/styles/theme.css'],
			// Custom component overrides, all under src/components/.
			components: {
				ThemeProvider: './src/components/ThemeProvider.astro',
				Header: './src/components/Header.astro',
				Hero: './src/components/Hero.astro',
				Footer: './src/components/Footer.astro',
			},
			editLink: {
				baseUrl: 'https://github.com/ChrisTitusTech/winutil/edit/main/docs/',
			},
			// Sidebar groups, top to bottom: User Guide, Code Reference, Help.
			sidebar: [
				{
					label: '使用指南',
					items: [
						{ label: '概述', slug: 'guides' },
						{ label: '快速开始', slug: 'guides/getting-started' },
						{ label: '应用', slug: 'guides/application' },
						{ label: '优化项', slug: 'guides/tweaks' },
						{ label: '功能', slug: 'guides/features' },
						{ label: '更新', slug: 'guides/updates' },
						{ label: '自动化', slug: 'guides/automation' },
						{ label: 'Win11 镜像制作', slug: 'guides/win11creator' },
					],
				},
				{
					label: '代码参考',
					items: [
						{ label: '架构与设计', slug: 'code-reference/architecture' },
						{ label: '问题分类命令', slug: 'code-reference/issue-triage' },
						{ label: '优化项参考', items: [{ autogenerate: { directory: 'code-reference/tweaks' } }] },
						{ label: '功能参考', items: [{ autogenerate: { directory: 'code-reference/features' } }] },
					],
				},
				{
					label: '帮助',
					items: [
						{ label: '常见问题', slug: 'faq' },
						{ label: '已知问题', slug: 'knownissues' },
						{ label: '参与贡献', slug: 'contributing' },
						{ label: siteLinks.forums.label, link: siteLinks.forums.href, attrs: { target: '_blank', rel: 'noreferrer' } },
					],
				},
				{ label: siteLinks.store.label, link: siteLinks.store.href, attrs: { target: '_blank', rel: 'noreferrer' } },
			],
		}),
	],
});
