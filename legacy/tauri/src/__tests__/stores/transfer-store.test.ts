import { beforeEach, describe, expect, it } from "vitest";
import { useTransferStore } from "../../stores/transfer-store";

describe("transferStore", () => {
  beforeEach(() => {
    useTransferStore.setState({ transfers: [] });
  });

  it("adds a transfer with active status", () => {
    useTransferStore.getState().addTransfer({
      jobId: 1,
      operation: "copy",
      srcFs: "gdrive:photos",
      dstFs: "local:/tmp/photos",
    });

    const transfers = useTransferStore.getState().transfers;
    expect(transfers).toHaveLength(1);
    expect(transfers[0].status).toBe("active");
    expect(transfers[0].jobId).toBe(1);
    expect(transfers[0].startedAt).toBeTruthy();
  });

  it("completes a transfer successfully", () => {
    useTransferStore.getState().addTransfer({
      jobId: 2,
      operation: "sync",
      srcFs: "s3:bucket",
      dstFs: "local:/data",
    });

    useTransferStore.getState().completeTransfer(2, true);

    const t = useTransferStore.getState().transfers[0];
    expect(t.status).toBe("completed");
    expect(t.completedAt).toBeTruthy();
    expect(t.error).toBeUndefined();
  });

  it("fails a transfer with error", () => {
    useTransferStore.getState().addTransfer({
      jobId: 3,
      operation: "copy",
      srcFs: "gdrive:docs",
      dstFs: "local:/docs",
    });

    useTransferStore.getState().completeTransfer(3, false, "Permission denied");

    const t = useTransferStore.getState().transfers[0];
    expect(t.status).toBe("failed");
    expect(t.error).toBe("Permission denied");
  });

  it("cancels a transfer", () => {
    useTransferStore.getState().addTransfer({
      jobId: 4,
      operation: "sync",
      srcFs: "a:",
      dstFs: "b:",
    });

    useTransferStore.getState().cancelTransfer(4);

    const t = useTransferStore.getState().transfers[0];
    expect(t.status).toBe("cancelled");
    expect(t.completedAt).toBeTruthy();
  });

  it("removes a transfer", () => {
    useTransferStore.getState().addTransfer({
      jobId: 5,
      operation: "copy",
      srcFs: "a:",
      dstFs: "b:",
    });

    useTransferStore.getState().removeTransfer(5);
    expect(useTransferStore.getState().transfers).toHaveLength(0);
  });

  it("clears completed transfers", () => {
    const store = useTransferStore.getState();
    store.addTransfer({
      jobId: 10,
      operation: "copy",
      srcFs: "a:",
      dstFs: "b:",
    });
    store.addTransfer({
      jobId: 11,
      operation: "sync",
      srcFs: "c:",
      dstFs: "d:",
    });
    store.addTransfer({
      jobId: 12,
      operation: "copy",
      srcFs: "e:",
      dstFs: "f:",
    });

    useTransferStore.getState().completeTransfer(10, true);
    useTransferStore.getState().completeTransfer(12, false, "err");

    useTransferStore.getState().clearCompleted();

    const transfers = useTransferStore.getState().transfers;
    expect(transfers).toHaveLength(1);
    expect(transfers[0].jobId).toBe(11);
    expect(transfers[0].status).toBe("active");
  });
});
