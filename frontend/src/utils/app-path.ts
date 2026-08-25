/** Vite public base URL, e.g. `/` or `/weknora/`. */
export function getViteBaseUrl(): string {
  const base = import.meta.env.BASE_URL || '/'
  return base.endsWith('/') ? base : `${base}/`
}

/** App path prefix without trailing slash, e.g. `` or `/weknora`. */
export function getAppPathPrefix(): string {
  const base = getViteBaseUrl()
  if (base === '/') return ''
  return base.replace(/\/+$/, '')
}

/** Resolve an in-app path like `/login` to `/weknora/login` when deployed under a subpath. */
export function resolveAppPath(path: string): string {
  const prefix = getAppPathPrefix()
  const normalized = path.startsWith('/') ? path : `/${path}`
  return prefix ? `${prefix}${normalized}` : normalized
}

export function isAppPath(pathname: string, appPath: string): boolean {
  return pathname === resolveAppPath(appPath)
}

export function pathnameStartsWithAppPath(pathname: string, appPath: string): boolean {
  return pathname.startsWith(resolveAppPath(appPath))
}

function resolveAppPathWithQuery(raw: string): string {
  const qIdx = raw.indexOf('?')
  const pathPart = qIdx >= 0 ? raw.slice(0, qIdx) : raw
  const queryPart = qIdx >= 0 ? raw.slice(qIdx) : ''
  const normalized = pathPart.startsWith('/') ? pathPart : `/${pathPart}`
  const prefix = getAppPathPrefix()
  const resolved =
    prefix && (normalized === prefix || normalized.startsWith(`${prefix}/`))
      ? normalized
      : resolveAppPath(normalized)
  return `${resolved}${queryPart}`
}

/** Turn backend invite_url into a copy-friendly absolute URL (includes subpath when deployed under one). */
export function absoluteAppURL(raw: string, origin?: string): string {
  if (!raw) return ''
  if (/^https?:\/\//i.test(raw)) {
    const prefix = getAppPathPrefix()
    if (!prefix) return raw
    try {
      const url = new URL(raw)
      if (url.pathname === prefix || url.pathname.startsWith(`${prefix}/`)) {
        return raw
      }
      url.pathname = resolveAppPath(url.pathname)
      return url.toString()
    } catch {
      return raw
    }
  }
  const base =
    origin ??
    (typeof window !== 'undefined' && window.location?.origin ? window.location.origin : '')
  return `${base}${resolveAppPathWithQuery(raw)}`
}
