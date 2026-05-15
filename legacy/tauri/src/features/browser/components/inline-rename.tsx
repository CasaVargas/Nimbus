import { useEffect, useRef, useState } from "react";
import { cn } from "@/lib/utils";

interface InlineRenameProps {
  name: string;
  onConfirm: (newName: string) => void;
  onCancel: () => void;
  className?: string;
}

export function InlineRename({
  name,
  onConfirm,
  onCancel,
  className,
}: InlineRenameProps) {
  const [value, setValue] = useState(name);
  const inputRef = useRef<HTMLInputElement>(null);

  useEffect(() => {
    const input = inputRef.current;
    if (!input) return;
    input.focus();
    // Select just the name part, not the extension
    const dotIndex = name.lastIndexOf(".");
    if (dotIndex > 0) {
      input.setSelectionRange(0, dotIndex);
    } else {
      input.select();
    }
  }, [name]);

  const handleConfirm = () => {
    const trimmed = value.trim();
    if (!trimmed || trimmed === name) {
      onCancel();
      return;
    }
    onConfirm(trimmed);
  };

  return (
    <input
      ref={inputRef}
      value={value}
      onChange={(e) => setValue(e.target.value)}
      onKeyDown={(e) => {
        if (e.key === "Enter") {
          e.preventDefault();
          handleConfirm();
        }
        if (e.key === "Escape") {
          e.preventDefault();
          onCancel();
        }
        // Stop propagation so row click/select handlers don't fire
        e.stopPropagation();
      }}
      onBlur={handleConfirm}
      onClick={(e) => e.stopPropagation()}
      onDoubleClick={(e) => e.stopPropagation()}
      className={cn(
        "h-6 w-full rounded border border-primary bg-background px-1 text-sm outline-none",
        className,
      )}
    />
  );
}
