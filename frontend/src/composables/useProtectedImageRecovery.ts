import { nextTick, watch } from 'vue'
import { clearProtectedFileFailureCache, hydrateProtectedFileImages } from '../utils/security.ts'
import type {
  HydrateProtectedFileOptions,
  ProtectedFileAccessContext,
} from '../utils/protectedFileAccess.ts'

/** Retry after persisted completion/full reveal or a corrected authorization scope. */
export function useProtectedImageRecovery(
  root: () => ParentNode | null | undefined,
  access: () => ProtectedFileAccessContext | undefined,
  ready: () => boolean,
  options?: () => HydrateProtectedFileOptions | undefined,
) {
  watch(
    [ready, () => JSON.stringify({ access: access() ?? null, options: options?.() ?? null })],
    ([done, scopeKey], [wasDone, previousScopeKey]) => {
      if (!(done && !wasDone) && (!previousScopeKey || scopeKey === previousScopeKey)) return
      clearProtectedFileFailureCache()
      void nextTick(() => hydrateProtectedFileImages(root(), access(), options?.()))
    },
    { immediate: true },
  )
}
