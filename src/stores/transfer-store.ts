import { create } from "zustand";
import { persist } from "zustand/middleware";

export type TransferStatus = "active" | "completed" | "failed" | "cancelled";

export interface Transfer {
  jobId: number;
  operation: "copy" | "sync";
  srcFs: string;
  dstFs: string;
  startedAt: string;
  completedAt?: string;
  status: TransferStatus;
  error?: string;
}

interface TransferState {
  transfers: Transfer[];
  addTransfer: (
    transfer: Omit<Transfer, "status" | "startedAt">,
  ) => void;
  completeTransfer: (
    jobId: number,
    success: boolean,
    error?: string,
  ) => void;
  cancelTransfer: (jobId: number) => void;
  removeTransfer: (jobId: number) => void;
  clearCompleted: () => void;
}

export const useTransferStore = create<TransferState>()(
  persist(
    (set) => ({
      transfers: [],

      addTransfer: (transfer) =>
        set((state) => ({
          transfers: [
            {
              ...transfer,
              status: "active",
              startedAt: new Date().toISOString(),
            },
            ...state.transfers,
          ],
        })),

      completeTransfer: (jobId, success, error) =>
        set((state) => ({
          transfers: state.transfers.map((t) =>
            t.jobId === jobId
              ? {
                  ...t,
                  status: success ? "completed" : "failed",
                  completedAt: new Date().toISOString(),
                  error: error,
                }
              : t,
          ),
        })),

      cancelTransfer: (jobId) =>
        set((state) => ({
          transfers: state.transfers.map((t) =>
            t.jobId === jobId
              ? {
                  ...t,
                  status: "cancelled",
                  completedAt: new Date().toISOString(),
                }
              : t,
          ),
        })),

      removeTransfer: (jobId) =>
        set((state) => ({
          transfers: state.transfers.filter((t) => t.jobId !== jobId),
        })),

      clearCompleted: () =>
        set((state) => ({
          transfers: state.transfers.filter((t) => t.status === "active"),
        })),
    }),
    { name: "streamcloned-transfers" },
  ),
);
