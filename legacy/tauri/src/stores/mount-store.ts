import { create } from "zustand";
import { persist } from "zustand/middleware";

export type VfsMode = "read-only" | "read-write";
export type MountBackend = "nfs" | "fuse" | "fileprovider";

export interface MountConfig {
  remote: string;
  mountPoint: string;
  vfsMode: VfsMode;
  autoMount: boolean;
  backend: MountBackend;
}

interface MountState {
  configs: MountConfig[];
  addConfig: (config: MountConfig) => void;
  removeConfig: (mountPoint: string) => void;
  toggleAutoMount: (mountPoint: string) => void;
}

export const useMountStore = create<MountState>()(
  persist(
    (set) => ({
      configs: [],

      addConfig: (config) =>
        set((state) => ({
          configs: [...state.configs, config],
        })),

      removeConfig: (mountPoint) =>
        set((state) => ({
          configs: state.configs.filter((c) => c.mountPoint !== mountPoint),
        })),

      toggleAutoMount: (mountPoint) =>
        set((state) => ({
          configs: state.configs.map((c) =>
            c.mountPoint === mountPoint ? { ...c, autoMount: !c.autoMount } : c,
          ),
        })),
    }),
    {
      name: "nimbus-mounts",
      version: 1,
      migrate: (persistedState, version) => {
        if (version === 0) {
          const state = persistedState as MountState;
          return {
            ...state,
            configs: (state.configs ?? []).map((c) => ({
              ...c,
              backend: c.backend ?? "fuse",
            })),
          };
        }
        return persistedState as MountState;
      },
    },
  ),
);
