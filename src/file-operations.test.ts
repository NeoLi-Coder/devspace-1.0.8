import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, readFile, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";
import test from "node:test";
import {
  copyWorkspacePath,
  moveWorkspacePath,
  renameWorkspacePath,
} from "./file-operations.js";

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

async function createWorkspace(t: test.TestContext): Promise<{ parent: string; root: string; outside: string }> {
  const parent = await mkdtemp(join(tmpdir(), "devspace-file-operations-test-"));
  const root = join(parent, "workspace");
  const outside = join(parent, "outside");
  await mkdir(root);
  await mkdir(outside);
  t.after(async () => {
    await rm(parent, { recursive: true, force: true });
  });
  return { parent, root, outside };
}

test("move/copy/rename support files, directories, merge, and overwrite semantics", async (t) => {
  const { root } = await createWorkspace(t);

  await writeFile(join(root, "move-source.txt"), "move");
  await moveWorkspacePath(root, { source: "move-source.txt", destination: "move-target.txt" });
  assert.equal(await exists(join(root, "move-source.txt")), false);
  assert.equal(await readFile(join(root, "move-target.txt"), "utf8"), "move");

  await writeFile(join(root, "copy-source.txt"), "copy");
  await copyWorkspacePath(root, { source: "copy-source.txt", destination: "copy-target.txt" });
  assert.equal(await readFile(join(root, "copy-source.txt"), "utf8"), "copy");
  assert.equal(await readFile(join(root, "copy-target.txt"), "utf8"), "copy");

  await writeFile(join(root, "rename-source.txt"), "rename");
  await renameWorkspacePath(root, { path: "rename-source.txt", newName: "renamed.txt" });
  assert.equal(await exists(join(root, "rename-source.txt")), false);
  assert.equal(await readFile(join(root, "renamed.txt"), "utf8"), "rename");

  await mkdir(join(root, "move-dir", "nested"), { recursive: true });
  await writeFile(join(root, "move-dir", "nested", "file.txt"), "directory move");
  await moveWorkspacePath(root, { source: "move-dir", destination: "moved-dir" });
  assert.equal(await exists(join(root, "move-dir")), false);
  assert.equal(await readFile(join(root, "moved-dir", "nested", "file.txt"), "utf8"), "directory move");

  await mkdir(join(root, "copy-dir", "nested"), { recursive: true });
  await writeFile(join(root, "copy-dir", "nested", "file.txt"), "directory copy");
  await copyWorkspacePath(root, { source: "copy-dir", destination: "copied-dir" });
  assert.equal(await readFile(join(root, "copy-dir", "nested", "file.txt"), "utf8"), "directory copy");
  assert.equal(await readFile(join(root, "copied-dir", "nested", "file.txt"), "utf8"), "directory copy");

  await mkdir(join(root, "merge-source", "same"), { recursive: true });
  await mkdir(join(root, "merge-target", "same"), { recursive: true });
  await writeFile(join(root, "merge-source", "source-only.txt"), "source");
  await writeFile(join(root, "merge-source", "same", "nested-source.txt"), "nested source");
  await writeFile(join(root, "merge-target", "target-only.txt"), "target");
  await writeFile(join(root, "merge-target", "same", "nested-target.txt"), "nested target");
  await copyWorkspacePath(root, { source: "merge-source", destination: "merge-target", merge: true });
  assert.equal(await readFile(join(root, "merge-target", "source-only.txt"), "utf8"), "source");
  assert.equal(await readFile(join(root, "merge-target", "target-only.txt"), "utf8"), "target");
  assert.equal(await readFile(join(root, "merge-target", "same", "nested-source.txt"), "utf8"), "nested source");
  assert.equal(await readFile(join(root, "merge-target", "same", "nested-target.txt"), "utf8"), "nested target");

  await mkdir(join(root, "no-merge-source"));
  await mkdir(join(root, "no-merge-target"));
  await assert.rejects(
    moveWorkspacePath(root, { source: "no-merge-source", destination: "no-merge-target" }),
    /merge=true/,
  );

  await mkdir(join(root, "conflict-source"));
  await mkdir(join(root, "conflict-target"));
  await writeFile(join(root, "conflict-source", "same.txt"), "source conflict");
  await writeFile(join(root, "conflict-target", "same.txt"), "target conflict");
  await assert.rejects(
    copyWorkspacePath(root, { source: "conflict-source", destination: "conflict-target", merge: true }),
    /File conflict/,
  );
  assert.equal(await readFile(join(root, "conflict-target", "same.txt"), "utf8"), "target conflict");

  await moveWorkspacePath(root, {
    source: "conflict-source",
    destination: "conflict-target",
    merge: true,
    overwrite: true,
  });
  assert.equal(await exists(join(root, "conflict-source")), false);
  assert.equal(await readFile(join(root, "conflict-target", "same.txt"), "utf8"), "source conflict");
});

test("move/copy/rename reject invalid and unsafe paths", async (t) => {
  const { root, outside } = await createWorkspace(t);
  await mkdir(join(root, "a"));
  await writeFile(join(root, "a", "file.txt"), "a");

  await assert.rejects(moveWorkspacePath(root, { source: "", destination: "target" }), /Source path is required/);
  await assert.rejects(copyWorkspacePath(root, { source: "a", destination: "" }), /Destination path is required/);
  await assert.rejects(moveWorkspacePath(root, { source: "missing", destination: "target" }), /Source does not exist/);
  await assert.rejects(moveWorkspacePath(root, { source: "../outside", destination: "target" }), /escapes the workspace/);
  await assert.rejects(copyWorkspacePath(root, { source: "a", destination: "../outside" }), /escapes the workspace/);

  const absoluteSource = join(root, "a");
  const absoluteDestination = join(root, "absolute-target");
  assert.equal(isAbsolute(absoluteSource), true);
  assert.equal(isAbsolute(absoluteDestination), true);
  await assert.rejects(moveWorkspacePath(root, { source: absoluteSource, destination: "target" }), /path must be relative/);
  await assert.rejects(copyWorkspacePath(root, { source: "a", destination: absoluteDestination }), /path must be relative/);

  await assert.rejects(moveWorkspacePath(root, { source: ".", destination: "target" }), /workspace root/);
  await assert.rejects(renameWorkspacePath(root, { path: ".", newName: "renamed-root" }), /workspace root/);
  await assert.rejects(moveWorkspacePath(root, { source: "a", destination: "a" }), /must be different/);
  await assert.rejects(moveWorkspacePath(root, { source: "a", destination: "a/b" }), /inside the source directory/);
  await assert.rejects(copyWorkspacePath(root, { source: "a", destination: "a/b" }), /inside the source directory/);

  await assert.rejects(renameWorkspacePath(root, { path: "a", newName: "../renamed" }), /path separators|traversal/);
  await assert.rejects(renameWorkspacePath(root, { path: "a", newName: "..\\renamed" }), /path separators|traversal/);
  await assert.rejects(renameWorkspacePath(root, { path: "a", newName: "nested/name" }), /path separators|traversal/);
  await assert.rejects(renameWorkspacePath(root, { path: "a", newName: "nested\\name" }), /path separators|traversal/);

  const existingFile = join(root, "existing.txt");
  await writeFile(existingFile, "existing");
  await writeFile(join(root, "replacement.txt"), "replacement");
  await assert.rejects(
    moveWorkspacePath(root, { source: "replacement.txt", destination: "existing.txt" }),
    /Destination already exists/,
  );
  await moveWorkspacePath(root, {
    source: "replacement.txt",
    destination: "existing.txt",
    overwrite: true,
  });
  assert.equal(await readFile(existingFile, "utf8"), "replacement");

  await writeFile(join(root, "copy-replacement.txt"), "copy replacement");
  await copyWorkspacePath(root, {
    source: "copy-replacement.txt",
    destination: "existing.txt",
    overwrite: true,
  });
  assert.equal(await readFile(join(root, "copy-replacement.txt"), "utf8"), "copy replacement");
  assert.equal(await readFile(existingFile, "utf8"), "copy replacement");

  await writeFile(join(root, "rename-existing.txt"), "existing rename target");
  await assert.rejects(
    renameWorkspacePath(root, { path: "existing.txt", newName: "rename-existing.txt" }),
    /Destination already exists/,
  );

  await mkdir(join(outside, "outside-dir"));
  await writeFile(join(outside, "outside-dir", "outside.txt"), "outside");
  const linkPath = join(root, "outside-link");
  try {
    await symlink(
      join(outside, "outside-dir"),
      linkPath,
      process.platform === "win32" ? "junction" : "dir",
    );
    await assert.rejects(
      copyWorkspacePath(root, { source: "outside-link", destination: "copied-link" }),
      /resolves outside the workspace/,
    );
    await assert.rejects(
      moveWorkspacePath(root, { source: "a", destination: "outside-link/new-a" }),
      /resolves outside the workspace/,
    );

    const sourceAlias = join(root, "source-alias");
    await symlink(join(root, "a"), sourceAlias, process.platform === "win32" ? "junction" : "dir");
    await assert.rejects(
      moveWorkspacePath(root, { source: "a", destination: "source-alias/moved" }),
      /inside the source directory/,
    );
    await assert.rejects(
      copyWorkspacePath(root, { source: "a", destination: "source-alias/copied" }),
      /inside the source directory/,
    );
    await assert.rejects(
      copyWorkspacePath(root, { source: "a", destination: "source-alias" }),
      /must be different/,
    );

    const rootAlias = join(root, "root-alias");
    await symlink(root, rootAlias, process.platform === "win32" ? "junction" : "dir");
    await assert.rejects(
      moveWorkspacePath(root, { source: "root-alias", destination: "renamed-root-alias" }),
      /workspace root/,
    );

    assert.equal(await readFile(join(outside, "outside-dir", "outside.txt"), "utf8"), "outside");
  } catch (error) {
    const code = (error as NodeJS.ErrnoException).code;
    if (code !== "EPERM" && code !== "EACCES") throw error;
  }
});

test("merge preflight prevents partial changes when a later conflict exists", async (t) => {
  const { root } = await createWorkspace(t);
  await mkdir(join(root, "source", "nested"), { recursive: true });
  await mkdir(join(root, "target", "nested"), { recursive: true });
  await writeFile(join(root, "source", "a-new.txt"), "new");
  await writeFile(join(root, "source", "nested", "z-conflict.txt"), "source");
  await writeFile(join(root, "target", "nested", "z-conflict.txt"), "target");

  await assert.rejects(
    moveWorkspacePath(root, { source: "source", destination: "target", merge: true }),
    /File conflict/,
  );
  assert.equal(await exists(join(root, "source", "a-new.txt")), true);
  assert.equal(await exists(join(root, "target", "a-new.txt")), false);
  assert.equal(await readFile(join(root, "target", "nested", "z-conflict.txt"), "utf8"), "target");
});
