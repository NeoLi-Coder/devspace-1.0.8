import { constants } from "node:fs";
import {
  access,
  copyFile,
  lstat,
  mkdir,
  readdir,
  realpath,
  rename as fsRename,
  rm,
} from "node:fs/promises";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { resolveConfinedPath } from "./apply-patch.js";

export interface MovePathInput {
  source: string;
  destination: string;
  overwrite?: boolean;
  merge?: boolean;
}

export interface CopyPathInput {
  source: string;
  destination: string;
  overwrite?: boolean;
  merge?: boolean;
}

export interface RenamePathInput {
  path: string;
  newName: string;
}

export interface FileOperationResult {
  source: string;
  destination: string;
  kind: "file" | "directory";
  overwrite: boolean;
  merge: boolean;
}

export async function moveWorkspacePath(
  root: string,
  input: MovePathInput,
): Promise<FileOperationResult> {
  return transferWorkspacePath(root, input, "move");
}

export async function copyWorkspacePath(
  root: string,
  input: CopyPathInput,
): Promise<FileOperationResult> {
  return transferWorkspacePath(root, input, "copy");
}

export async function renameWorkspacePath(
  root: string,
  input: RenamePathInput,
): Promise<FileOperationResult> {
  validateRenameName(input.newName);
  const source = await resolveConfinedPath(root, input.path);
  const rootPath = await resolveConfinedPath(root, ".");
  if (source === rootPath) {
    throw new Error("Refusing to rename the workspace root.");
  }

  const destinationInput = join(dirname(input.path), input.newName);
  return moveWorkspacePath(root, {
    source: input.path,
    destination: destinationInput,
  });
}

async function transferWorkspacePath(
  root: string,
  input: MovePathInput | CopyPathInput,
  operation: "move" | "copy",
): Promise<FileOperationResult> {
  if (!input.source) throw new Error("Source path is required.");
  if (!input.destination) throw new Error("Destination path is required.");

  const source = await resolveConfinedPath(root, input.source);
  const destination = await resolveConfinedPath(root, input.destination);
  const rootPath = await resolveConfinedPath(root, ".");
  const sourceIdentity = await canonicalProspectivePath(root, source);
  const destinationIdentity = await canonicalProspectivePath(root, destination);

  if (samePath(sourceIdentity, rootPath)) {
    throw new Error(`Refusing to ${operation} the workspace root.`);
  }
  if (samePath(sourceIdentity, destinationIdentity)) {
    throw new Error("Source and destination must be different.");
  }

  let sourceStats;
  try {
    sourceStats = await lstat(source);
  } catch (error) {
    if (isErrnoException(error) && (error.code === "ENOENT" || error.code === "ENOTDIR")) {
      throw new Error(`Source does not exist: ${input.source}`);
    }
    throw error;
  }

  const kind = sourceStats.isDirectory() ? "directory" : "file";
  if (kind === "directory" && isInside(sourceIdentity, destinationIdentity)) {
    throw new Error("Destination cannot be inside the source directory.");
  }

  const overwrite = input.overwrite === true;
  const merge = input.merge === true;
  const destinationExists = await pathExists(destination);

  if (kind === "file") {
    if (destinationExists && !overwrite) {
      throw new Error(`Destination already exists: ${input.destination}`);
    }
    if (destinationExists && (await lstat(destination)).isDirectory()) {
      throw new Error(`Destination is a directory: ${input.destination}`);
    }

    await mkdir(dirname(destination), { recursive: true });
    if (operation === "move") {
      await moveFile(source, destination, overwrite);
    } else {
      await copyFile(source, destination, overwrite ? 0 : constants.COPYFILE_EXCL);
    }
    return { source: input.source, destination: input.destination, kind, overwrite, merge };
  }

  if (!destinationExists) {
    await preflightDirectory(root, source, destination, overwrite, false);
    await mkdir(dirname(destination), { recursive: true });
    if (operation === "move") {
      try {
        await fsRename(source, destination);
      } catch (error) {
        if (!isErrnoException(error) || error.code !== "EXDEV") throw error;
        await copyDirectory(root, source, destination, overwrite, false);
        await rm(source, { recursive: true });
      }
    } else {
      await copyDirectory(root, source, destination, overwrite, false);
    }
    return { source: input.source, destination: input.destination, kind, overwrite, merge };
  }

  if (!(await lstat(destination)).isDirectory()) {
    throw new Error(`Destination is not a directory: ${input.destination}`);
  }
  if (!merge) {
    throw new Error(`Destination directory already exists; set merge=true to combine it: ${input.destination}`);
  }

  await preflightDirectory(root, source, destination, overwrite, true);
  await transferDirectoryEntries(root, source, destination, operation, overwrite);
  if (operation === "move") await rm(source, { recursive: true });
  return { source: input.source, destination: input.destination, kind, overwrite, merge };
}

async function preflightDirectory(
  root: string,
  source: string,
  destination: string,
  overwrite: boolean,
  merge: boolean,
): Promise<void> {
  await assertResolvedAbsoluteInsideWorkspace(root, source);
  await assertResolvedAbsoluteInsideWorkspace(root, destination);

  const destinationExists = await pathExists(destination);
  if (destinationExists) {
    const destinationStats = await lstat(destination);
    if (!destinationStats.isDirectory()) {
      throw new Error(`Destination is not a directory: ${relative(root, destination)}`);
    }
    if (!merge) {
      throw new Error(`Destination directory already exists: ${relative(root, destination)}`);
    }
  }

  for (const entry of await readdir(source, { withFileTypes: true })) {
    const sourceChild = join(source, entry.name);
    const destinationChild = join(destination, entry.name);
    await assertResolvedAbsoluteInsideWorkspace(root, sourceChild);
    await assertResolvedAbsoluteInsideWorkspace(root, destinationChild);

    const childDestinationExists = await pathExists(destinationChild);
    if (entry.isDirectory()) {
      if (!childDestinationExists) {
        await preflightDirectory(root, sourceChild, destinationChild, overwrite, false);
        continue;
      }
      if (!(await lstat(destinationChild)).isDirectory()) {
        throw new Error(`Directory conflict at ${relative(root, destinationChild)}.`);
      }
      await preflightDirectory(root, sourceChild, destinationChild, overwrite, true);
      continue;
    }

    if (!childDestinationExists) continue;
    const destinationStats = await lstat(destinationChild);
    if (destinationStats.isDirectory()) {
      throw new Error(`File conflict with directory at ${relative(root, destinationChild)}.`);
    }
    if (!overwrite) {
      throw new Error(`File conflict at ${relative(root, destinationChild)}; set overwrite=true to replace it.`);
    }
  }
}

async function transferDirectoryEntries(
  root: string,
  source: string,
  destination: string,
  operation: "move" | "copy",
  overwrite: boolean,
): Promise<void> {
  for (const entry of await readdir(source, { withFileTypes: true })) {
    const sourceChild = join(source, entry.name);
    const destinationChild = join(destination, entry.name);

    await assertResolvedAbsoluteInsideWorkspace(root, sourceChild);
    await assertResolvedAbsoluteInsideWorkspace(root, destinationChild);

    const destinationExists = await pathExists(destinationChild);
    if (entry.isDirectory()) {
      if (!destinationExists) {
        if (operation === "move") {
          try {
            await fsRename(sourceChild, destinationChild);
            continue;
          } catch (error) {
            if (!isErrnoException(error) || error.code !== "EXDEV") throw error;
          }
        }
        await copyDirectory(root, sourceChild, destinationChild, overwrite, false);
        if (operation === "move") await rm(sourceChild, { recursive: true });
        continue;
      }

      if (!(await lstat(destinationChild)).isDirectory()) {
        throw new Error(`Directory conflict at ${relative(root, destinationChild)}.`);
      }
      await transferDirectoryEntries(root, sourceChild, destinationChild, operation, overwrite);
      if (operation === "move") await rm(sourceChild, { recursive: true });
      continue;
    }

    if (destinationExists) {
      const destinationStats = await lstat(destinationChild);
      if (destinationStats.isDirectory()) {
        throw new Error(`File conflict with directory at ${relative(root, destinationChild)}.`);
      }
      if (!overwrite) {
        throw new Error(`File conflict at ${relative(root, destinationChild)}; set overwrite=true to replace it.`);
      }
    }

    if (operation === "move") {
      await moveFile(sourceChild, destinationChild, overwrite);
    } else {
      await copyFile(sourceChild, destinationChild, overwrite ? 0 : constants.COPYFILE_EXCL);
    }
  }
}

async function copyDirectory(
  root: string,
  source: string,
  destination: string,
  overwrite: boolean,
  merge: boolean,
): Promise<void> {
  const destinationExists = await pathExists(destination);
  if (destinationExists && !merge) {
    throw new Error(`Destination directory already exists: ${relative(root, destination)}`);
  }
  if (!destinationExists) await mkdir(destination, { recursive: true });
  await transferDirectoryEntries(root, source, destination, "copy", overwrite);
}

async function moveFile(source: string, destination: string, overwrite: boolean): Promise<void> {
  if (!overwrite) {
    try {
      await fsRename(source, destination);
      return;
    } catch (error) {
      if (!isErrnoException(error) || error.code !== "EXDEV") throw error;
      await copyFile(source, destination, constants.COPYFILE_EXCL);
      await rm(source);
      return;
    }
  }

  try {
    await fsRename(source, destination);
  } catch (error) {
    if (isErrnoException(error) && (error.code === "EEXIST" || error.code === "EPERM")) {
      await rm(destination);
      await fsRename(source, destination);
      return;
    }
    if (isErrnoException(error) && error.code === "EXDEV") {
      await copyFile(source, destination);
      await rm(source);
      return;
    }
    throw error;
  }
}

async function assertResolvedAbsoluteInsideWorkspace(root: string, absolutePath: string): Promise<void> {
  const relativePath = relative(await resolveConfinedPath(root, "."), absolutePath);
  await resolveConfinedPath(root, relativePath || ".");
}

async function canonicalProspectivePath(root: string, absolutePath: string): Promise<string> {
  let existing = absolutePath;
  const missingSegments: string[] = [];

  while (true) {
    try {
      const canonicalExisting = await realpath(existing);
      const canonicalPath = resolve(canonicalExisting, ...missingSegments);
      await assertResolvedAbsoluteInsideWorkspace(root, canonicalPath);
      return canonicalPath;
    } catch (error) {
      if (!isErrnoException(error) || error.code !== "ENOENT") throw error;
      const parent = dirname(existing);
      if (parent === existing) throw error;
      missingSegments.unshift(basename(existing));
      existing = parent;
    }
  }
}

function validateRenameName(newName: string): void {
  if (!newName || newName.includes("\0") || isAbsolute(newName)) {
    throw new Error("newName must be a simple file or directory name.");
  }
  if (newName === "." || newName === ".." || newName.includes("/") || newName.includes("\\")) {
    throw new Error("newName must not contain path separators or traversal segments.");
  }
  if (basename(newName) !== newName) {
    throw new Error("newName must be a simple file or directory name.");
  }
}

function isInside(parent: string, candidate: string): boolean {
  const relationship = relative(parent, candidate);
  return relationship !== "" && !relationship.startsWith("..") && !isAbsolute(relationship);
}

function samePath(a: string, b: string): boolean {
  if (process.platform === "win32") return resolve(a).toLowerCase() === resolve(b).toLowerCase();
  return resolve(a) === resolve(b);
}

async function pathExists(path: string): Promise<boolean> {
  try {
    await access(path, constants.F_OK);
    return true;
  } catch (error) {
    if (isErrnoException(error) && (error.code === "ENOENT" || error.code === "ENOTDIR")) return false;
    throw error;
  }
}

function isErrnoException(error: unknown): error is NodeJS.ErrnoException {
  return error instanceof Error && "code" in error;
}
