import { ref } from "vue";

export interface ConfirmDialog {
  id: string;
  message: string;
  confirmText?: string;
  cancelText?: string;
  type?: "warning" | "danger" | "info";
  resolve: (value: boolean) => void;
}

const currentDialog = ref<ConfirmDialog | null>(null);
let dialogId = 0;

export function useConfirm() {
  const confirm = (
    message: string,
    options: {
      confirmText?: string;
      cancelText?: string;
      type?: "warning" | "danger" | "info";
    } = {},
  ): Promise<boolean> => {
    return new Promise((resolve) => {
      const id = `confirm-${dialogId++}`;
      currentDialog.value = {
        id,
        message,
        confirmText: options.confirmText || "Confirm",
        cancelText: options.cancelText || "Cancel",
        type: options.type || "warning",
        resolve,
      };
    });
  };

  const resolveDialog = (value: boolean) => {
    if (currentDialog.value) {
      currentDialog.value.resolve(value);
      currentDialog.value = null;
    }
  };

  return {
    currentDialog,
    confirm,
    resolveDialog,
  };
}
