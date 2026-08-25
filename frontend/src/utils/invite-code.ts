/** Normalize user input: bare code, or full/partial invite link pasted into the code field. */
export function normalizeInviteCode(raw: string): string {
  const trimmed = raw.trim()
  if (!trimmed) return ''

  const fromQuery = (value: string | null): string => {
    const code = value?.trim() ?? ''
    return code ? code.toLowerCase() : ''
  }

  if (trimmed.includes('://')) {
    try {
      const url = new URL(trimmed)
      const code = fromQuery(url.searchParams.get('code'))
        || fromQuery(url.searchParams.get('invite_code'))
      if (code) return code
    } catch {
      // fall through
    }
  }

  const match = trimmed.match(/(?:^|[?&])(?:code|invite_code)=([0-9a-fA-F]{8,32})/)
  if (match?.[1]) return match[1].toLowerCase()

  return trimmed.toLowerCase()
}
