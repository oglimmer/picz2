import {
  ref,
  computed,
  onMounted,
  onBeforeUnmount,
  type Ref,
  type ComputedRef,
} from "vue";

/**
 * Open/close behaviour for a dropdown anchored to a trigger.
 *
 * <p>The open menu is tracked module-wide, so opening any menu closes every other one. That keeps
 * a page with several dropdowns (masthead account, album manage, sort, tag-all) from having to
 * coordinate them by hand, and it means a stale menu can never be left behind another.
 */
const openMenuId = ref<number | null>(null);
let nextId = 0;

export interface MenuComposable {
  isOpen: ComputedRef<boolean>;
  toggle: () => void;
  close: () => void;
}

/**
 * @param root element that counts as "inside" the menu — a click anywhere else closes it.
 */
export function useMenu(root: Ref<HTMLElement | null>): MenuComposable {
  const id = ++nextId;
  const isOpen = computed(() => openMenuId.value === id);

  function toggle(): void {
    openMenuId.value = isOpen.value ? null : id;
  }

  function close(): void {
    if (isOpen.value) openMenuId.value = null;
  }

  function onDocumentClick(event: MouseEvent): void {
    if (!isOpen.value) return;
    if (!root.value?.contains(event.target as Node)) close();
  }

  function onKeydown(event: KeyboardEvent): void {
    if (event.key === "Escape") close();
  }

  onMounted(() => {
    document.addEventListener("click", onDocumentClick);
    document.addEventListener("keydown", onKeydown);
  });

  onBeforeUnmount(() => {
    document.removeEventListener("click", onDocumentClick);
    document.removeEventListener("keydown", onKeydown);
    close();
  });

  return { isOpen, toggle, close };
}
