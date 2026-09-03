import { lstat, rm, rmdir } from "node:fs/promises";
import { resolveConfinedPath } from "./apply-patch.js";

export interface DeletePathInput {
  path: string;
  recursive?: boolean;
}

export interface DeletePathResult {
  path: string;
  kind: "file" | "directory";
  recursive: boolean;
}

export async function deleteWorkspacePath(
  root: string,
  input: DeletePathInput,
): Promise<DeletePathResult> {
  const target = await resolveConfinedPath(root, input.path);
  const rootPath = await resolveConfinedPath(root, ".");

  if (target === rootPath) {
    throw new Error("Refusing to delete the workspace root.");
  }

  let metadata;
  try {
    metadata = await lstat(target);
  } catch (error) {
    if (isErrnoException(error) && (error.code === "ENOENT" || error.code === "ENOTDIR")) {
      throw new Error(`Path does not exist: ${input.path}`);
    }
    throw error;
  }

  if (metadata.isDirectory()) {
    if (input.recursive === true) {
      await rm(target, { recursive: true });
      return { path: input.path, kind: "directory", recursive: true };
    }

    try {
      await rmdir(target);
    } catch (error) {
      if (isErrnoException(error) && (error.code === "ENOTEMPTY" || error.code === "EEXIST")) {
        throw new Error(`Directory is not empty; set recursive=true to delete it: ${input.path}`);
      }
      throw error;
    }

    return { path: input.path, kind: "directory", recursive: false };
  }

  await rm(target);
  return { path: input.path, kind: "file", recursive: false };
}

function isErrnoException(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
