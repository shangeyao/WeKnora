export interface KnowledgeDownloadItem {
  id: string;
  original_file_name?: string;
  file_name?: string;
  title?: string;
  type?: string;
  file_type?: string;
  source?: string;
}

/** User-facing document name for cards and headers (title takes precedence over file_name). */
export function resolveKnowledgeDisplayName(
  item: Pick<KnowledgeDownloadItem, 'title' | 'file_name' | 'source' | 'type' | 'file_type'>,
  fallback = '',
): string {
  const raw = (item.title || item.file_name || item.source || fallback).trim();
  if (!raw) return fallback;
  if (item.type === 'file') {
    const fileType = (item.file_type || '').toLowerCase();
    const dot = raw.lastIndexOf('.');
    if (dot > 0 && fileType && raw.substring(dot + 1).toLowerCase() === fileType) {
      return raw.substring(0, dot);
    }
  }
  return raw;
}

export function resolveKnowledgeDownloadFileName(item: KnowledgeDownloadItem): string {
  const baseName = item.original_file_name || item.file_name || item.title || item.id;
  if (item.type === 'manual' && !baseName.toLowerCase().endsWith('.md')) {
    return `${baseName}.md`;
  }
  return baseName;
}
