/**
 * Rotates an image by 90 degrees counterclockwise (to the left)
 * @param file - The image file to rotate
 * @returns Promise that resolves to the rotated image as a File
 */
export async function rotateImageLeft(file: File): Promise<File> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");

    if (!ctx) {
      reject(new Error("Failed to get canvas context"));
      return;
    }

    img.onload = () => {
      // For a 90-degree counterclockwise rotation:
      // - The new width becomes the old height
      // - The new height becomes the old width
      canvas.width = img.height;
      canvas.height = img.width;

      // Translate to the center of the new canvas dimensions
      ctx.translate(canvas.width / 2, canvas.height / 2);

      // Rotate 90 degrees counterclockwise (-90 degrees = -π/2 radians)
      ctx.rotate(-Math.PI / 2);

      // Draw the image centered on the rotation point
      ctx.drawImage(img, -img.width / 2, -img.height / 2);

      // Convert canvas to blob and then to File
      canvas.toBlob(
        (blob) => {
          if (!blob) {
            reject(new Error("Failed to create blob from canvas"));
            return;
          }

          // Create a new File with the same name and type as the original
          const rotatedFile = new File([blob], file.name, {
            type: file.type,
            lastModified: Date.now(),
          });

          resolve(rotatedFile);
        },
        file.type,
        0.95, // Quality for JPEG images
      );
    };

    img.onerror = () => {
      reject(new Error("Failed to load image"));
    };

    // Load the image from the file
    img.src = URL.createObjectURL(file);
  });
}

/**
 * Rotates an image by 90 degrees clockwise (to the right)
 * @param file - The image file to rotate
 * @returns Promise that resolves to the rotated image as a File
 */
export async function rotateImageRight(file: File): Promise<File> {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const canvas = document.createElement("canvas");
    const ctx = canvas.getContext("2d");

    if (!ctx) {
      reject(new Error("Failed to get canvas context"));
      return;
    }

    img.onload = () => {
      canvas.width = img.height;
      canvas.height = img.width;

      ctx.translate(canvas.width / 2, canvas.height / 2);

      // Rotate 90 degrees clockwise (π/2 radians)
      ctx.rotate(Math.PI / 2);

      ctx.drawImage(img, -img.width / 2, -img.height / 2);

      canvas.toBlob(
        (blob) => {
          if (!blob) {
            reject(new Error("Failed to create blob from canvas"));
            return;
          }

          const rotatedFile = new File([blob], file.name, {
            type: file.type,
            lastModified: Date.now(),
          });

          resolve(rotatedFile);
        },
        file.type,
        0.95,
      );
    };

    img.onerror = () => {
      reject(new Error("Failed to load image"));
    };

    img.src = URL.createObjectURL(file);
  });
}
