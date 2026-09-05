# Composables — state scope

Two kinds live here, and the difference is deliberate. Each file says which it is in its header.

**Module singletons** hold their `ref`s at module level, so every caller shares one state:
`useAuth`, `useTags`, `useSettings`, `useNotifications`, `useConfirm`, `useCapabilities`,
`useMenu` (the open-menu id), `useRegionNames` (the name cache), `useVersion`'s build constants.
These are app-wide facts — who is signed in, which tags exist, which toast is showing — and two
components disagreeing about them would be a bug.

**Per-instance composables** create fresh state on every call: `useFiles`, `useAlbums`,
`useStorageBackends`, `useSlideshow`, `useSlideshowPlayback`, `usePresentationGroups`,
`useProcessingPoller`, `useAnalytics`, and everything under `gallery/`. Their state belongs to one
view: the file list of *this* gallery, the recordings of *this* album. A view calls each once in its
`setup` and passes what children need down as props. Calling one of these twice in the same view
gives two unrelated states — that is the contract, not an accident.

Rule of thumb when adding one: if a second component could legitimately read the same value
without being handed it, make it a singleton; otherwise keep it per instance.
