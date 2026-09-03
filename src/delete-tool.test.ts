import assert from "node:assert/strict";
import { access, mkdir, mkdtemp, rm, symlink, writeFile } from "node:fs/promises";
import { tmpdir } from "node:os";
import { isAbsolute, join } from "node:path";
import test from "node:test";
import { deleteWorkspacePath } from "./delete-tool.js";

async function exists(path: string): Promise<boolean> {
  try {
    await access(path);
    return true;
  } catch {
    return false;
  }
}

test("deleteWorkspacePath enforces workspace deletion boundaries", async (t) => {
  const parent = await mkdtemp(join(tmpdir(), "devspace-delete-test-"));
  const root = join(parent, "workspace");
  const outside = join(parent, "outside");
  await mkdir(root);
  await mkdir(outside);

  t.after(async () => {
    await rm(parent, { recursive: true, force: true });
  });

  const file = join(root, "file.txt");
  await writeFile(file, "file");
  await deleteWorkspacePath(root, { path: "file.txt" });
  assert.equal(await exists(file), false);

  const emptyDir = join(root, "empty");
  await mkdir(emptyDir);
  await deleteWorkspacePath(root, { path: "empty" });
  assert.equal(await exists(emptyDir), false);

  const nonEmptyDir = join(root, "non-empty");
  await mkdir(nonEmptyDir);
  await writeFile(join(nonEmptyDir, "child.txt"), "child");
  await assert.rejects(
    deleteWorkspacePath(root, { path: "non-empty" }),
    /Directory is not empty; set recursive=true/,
  );
  assert.equal(await exists(nonEmptyDir), true);
  await deleteWorkspacePath(root, { path: "non-empty", recursive: true });
  assert.equal(await exists(nonEmptyDir), false);

  await assert.rejects(deleteWorkspacePath(root, { path: ".", recursive: true }), /workspace root/);
  await assert.rejects(deleteWorkspacePath(root, { path: "../outside" }), /escapes the workspace/);

  const absolute = join(root, "absolute.txt");
  assert.equal(isAbsolute(absolute), true);
  await writeFile(absolute, "absolute");
  await assert.rejects(deleteWorkspacePath(root, { path: absolute }), /path must be relative to the workspace/);
  assert.equal(await exists(absolute), true);

  await assert.rejects(deleteWorkspacePath(root, { path: "missing.txt" }), /Path does not exist/);

  const outsideFile = join(outside, "outside.txt");
  await writeFile(outsideFile, "outside");
  const outsideDir = join(outside, "directory");
  await mkdir(outsideDir);
  await writeFile(join(outsideDir, "preserve.txt"), "preserve");

  if (process.platform === "win32") {
    const junction = join(root, "outside-junction");
    await symlink(outsideDir, junction, "junction");
    await assert.rejects(
      deleteWorkspacePath(root, { path: "outside-junction", recursive: true }),
      /resolves outside the workspace/,
    );
    assert.equal(await exists(join(outsideDir, "preserve.txt")), true);

    const nested = join(root, "nested-junction");
    await mkdir(nested);
    await symlink(outsideDir, join(nested, "link"), "junction");
    await deleteWorkspacePath(root, { path: "nested-junction", recursive: true });
    assert.equal(await exists(nested), false);
    assert.equal(await exists(join(outsideDir, "preserve.txt")), true);

    const fileLink = join(root, "outside-file-link");
    try {
      await symlink(outsideFile, fileLink, "file");
      await assert.rejects(
        deleteWorkspacePath(root, { path: "outside-file-link" }),
        /resolves outside the workspace/,
      );
      assert.equal(await exists(outsideFile), true);
    } catch (error) {
      const code = (error as NodeJS.ErrnoException).code;
      if (code !== "EPERM" && code !== "EACCES") throw error;
    }
  } else {
    const dirLink = join(root, "outside-dir-link");
    await symlink(outsideDir, dirLink, "dir");
    await assert.rejects(
      deleteWorkspacePath(root, { path: "outside-dir-link", recursive: true }),
      /resolves outside the workspace/,
    );
    assert.equal(await exists(join(outsideDir, "preserve.txt")), true);

    const fileLink = join(root, "outside-file-link");
    await symlink(outsideFile, fileLink, "file");
    await assert.rejects(
      deleteWorkspacePath(root, { path: "outside-file-link" }),
      /resolves outside the workspace/,
    );
    assert.equal(await exists(outsideFile), true);
  }
});
