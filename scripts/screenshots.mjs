// Browse a running site and collect evidence for the Reviewer:
// screenshots per page x viewport x colour scheme, automated accessibility violations (axe),
// and console or network errors.
//
// usage: node screenshots.mjs <base-url> <out-dir>
// env:   CREW_PAGES (json array of paths), CREW_VIEWPORTS (json array of {name,width,height}),
//        CREW_SCHEMES (json array), CREW_EXTRA_HEADERS (json object, for protected previews)
import fs from 'node:fs'
import path from 'node:path'
import { chromium } from 'playwright'
import AxeBuilder from '@axe-core/playwright'

const [, , baseUrl, outDir] = process.argv
if (!baseUrl || !outDir) {
  console.error('usage: node screenshots.mjs <base-url> <out-dir>')
  process.exit(2)
}

const pages = JSON.parse(process.env.CREW_PAGES || '["/"]')
const viewports = JSON.parse(
  process.env.CREW_VIEWPORTS ||
    '[{"name":"mobile","width":390,"height":844},{"name":"desktop","width":1440,"height":900}]',
)
const schemes = JSON.parse(process.env.CREW_SCHEMES || '["light","dark"]')
const extraHTTPHeaders = JSON.parse(process.env.CREW_EXTRA_HEADERS || '{}')

fs.mkdirSync(outDir, { recursive: true })
const slug = (p) => (p === '/' ? 'home' : p.replace(/^\/|\/$/g, '').replace(/[^a-z0-9]+/gi, '-'))

const manifest = { shots: [], a11y: [], runtime: [] }
const browser = await chromium.launch()

try {
  for (const scheme of schemes) {
    for (const viewport of viewports) {
      const context = await browser.newContext({
        viewport: { width: viewport.width, height: viewport.height },
        colorScheme: scheme,
        extraHTTPHeaders,
      })
      for (const p of pages) {
        const page = await context.newPage()
        const problems = []
        page.on('pageerror', (e) => problems.push(`pageerror: ${e.message}`))
        page.on('console', (m) => m.type() === 'error' && problems.push(`console: ${m.text()}`))
        page.on('requestfailed', (r) => problems.push(`requestfailed: ${r.url()} ${r.failure()?.errorText ?? ''}`))
        page.on('response', (r) => r.status() >= 400 && problems.push(`http ${r.status()}: ${r.url()}`))

        try {
          const res = await page.goto(new URL(p, baseUrl).toString(), { waitUntil: 'networkidle', timeout: 45000 })
          if (res && res.status() >= 400) problems.push(`page returned http ${res.status()}`)

          // Scroll through the page so scroll-triggered reveal animations run before the screenshot.
          await page.evaluate(async () => {
            const step = Math.max(400, Math.floor(window.innerHeight * 0.8))
            for (let y = 0; y < document.body.scrollHeight; y += step) {
              window.scrollTo(0, y)
              await new Promise((r) => setTimeout(r, 120))
            }
            window.scrollTo(0, 0)
            await new Promise((r) => setTimeout(r, 250))
          })

          const file = `${slug(p)}--${viewport.name}--${scheme}.jpg`
          await page.screenshot({ path: path.join(outDir, file), fullPage: true, type: 'jpeg', quality: 65 })
          manifest.shots.push({ page: p, viewport: viewport.name, scheme, file })

          const axe = await new AxeBuilder({ page }).withTags(['wcag2a', 'wcag2aa']).analyze()
          manifest.a11y.push({
            page: p,
            viewport: viewport.name,
            scheme,
            violations: axe.violations.map((v) => ({
              id: v.id,
              impact: v.impact,
              help: v.help,
              nodes: v.nodes.length,
              sample: v.nodes[0]?.target?.join(' ') ?? '',
            })),
          })
        } catch (e) {
          problems.push(`visit failed: ${e.message}`)
        }
        if (problems.length) manifest.runtime.push({ page: p, viewport: viewport.name, scheme, problems: [...new Set(problems)].slice(0, 10) })
        await page.close()
      }
      await context.close()
    }
  }
} finally {
  await browser.close()
}

fs.writeFileSync(path.join(outDir, 'manifest.json'), JSON.stringify(manifest, null, 2))
console.log(`evidence: ${manifest.shots.length} screenshots, ${manifest.a11y.reduce((n, a) => n + a.violations.length, 0)} axe violations, ${manifest.runtime.length} pages with runtime problems`)
