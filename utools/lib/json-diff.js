/**
 * 结构化 JSON Diff / Apply（对照 mac DotJSONCore.JSONDiff）。
 * 浏览器侧纯 JS，依赖 DotJSONCore.format；无第三方依赖。
 */
(function (global) {
  "use strict";

  const SOFT_INPUT_BYTE_LIMIT = 2000000;

  function utf8ByteLength(text) {
    if (typeof TextEncoder !== "undefined") {
      return new TextEncoder().encode(String(text)).length;
    }
    if (typeof Buffer !== "undefined") {
      return Buffer.byteLength(String(text), "utf8");
    }
    return String(text).length;
  }

  function isPlainObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
  }

  function deepEqual(a, b) {
    if (a === b) return true;
    if (a === null || b === null) return a === b;
    if (typeof a !== typeof b) return false;
    if (Array.isArray(a)) {
      if (!Array.isArray(b) || a.length !== b.length) return false;
      for (let i = 0; i < a.length; i += 1) {
        if (!deepEqual(a[i], b[i])) return false;
      }
      return true;
    }
    if (isPlainObject(a)) {
      if (!isPlainObject(b)) return false;
      const aKeys = Object.keys(a).sort();
      const bKeys = Object.keys(b).sort();
      if (aKeys.length !== bKeys.length) return false;
      for (let i = 0; i < aKeys.length; i += 1) {
        if (aKeys[i] !== bKeys[i]) return false;
        if (!deepEqual(a[aKeys[i]], b[bKeys[i]])) return false;
      }
      return true;
    }
    return false;
  }

  function cloneValue(value) {
    return JSON.parse(JSON.stringify(value));
  }

  function pathString(parts) {
    return parts.map((p) => (typeof p === "object" && p !== null ? p.value : p)).join(".");
  }

  function resolvePathParts(pathOrParts) {
    if (Array.isArray(pathOrParts)) return pathOrParts;
    return parsePath(pathOrParts);
  }

  function parsePath(path) {
    if (!path) return [];
    return String(path).split(".").map((segment) => {
      if (/^\d+$/.test(segment)) return { type: "index", value: Number(segment) };
      return { type: "key", value: segment };
    });
  }

  function parseSide(text, side) {
    const trimmed = String(text ?? "").replace(/^\uFEFF/, "");
    try {
      return JSON.parse(trimmed);
    } catch (err) {
      const message = err && err.message ? err.message : String(err);
      const error = new Error(message);
      error.side = side;
      throw error;
    }
  }

  function structuredDiff(left, right, pathParts) {
    const parts = pathParts || [];
    if (deepEqual(left, right)) return [];

    if (isPlainObject(left) && isPlainObject(right)) {
      const rows = [];
      const allKeys = Array.from(
        new Set([...Object.keys(left), ...Object.keys(right)])
      ).sort();
      for (const key of allKeys) {
        const childParts = parts.concat([{ type: "key", value: key }]);
        const child = pathString(childParts);
        const hasLeft = Object.prototype.hasOwnProperty.call(left, key);
        const hasRight = Object.prototype.hasOwnProperty.call(right, key);
        if (!hasLeft && hasRight) {
          rows.push({
            kind: "add",
            path: child,
            pathParts: childParts,
            leftValue: undefined,
            rightValue: right[key],
          });
        } else if (hasLeft && !hasRight) {
          rows.push({
            kind: "remove",
            path: child,
            pathParts: childParts,
            leftValue: left[key],
            rightValue: undefined,
          });
        } else {
          rows.push(...structuredDiff(left[key], right[key], childParts));
        }
      }
      return rows;
    }

    if (Array.isArray(left) && Array.isArray(right)) {
      const rows = [];
      const maxCount = Math.max(left.length, right.length);
      for (let index = 0; index < maxCount; index += 1) {
        const childParts = parts.concat([{ type: "index", value: index }]);
        const child = pathString(childParts);
        const hasLeft = index < left.length;
        const hasRight = index < right.length;
        if (!hasLeft && hasRight) {
          rows.push({
            kind: "add",
            path: child,
            pathParts: childParts,
            leftValue: undefined,
            rightValue: right[index],
          });
        } else if (hasLeft && !hasRight) {
          rows.push({
            kind: "remove",
            path: child,
            pathParts: childParts,
            leftValue: left[index],
            rightValue: undefined,
          });
        } else {
          rows.push(...structuredDiff(left[index], right[index], childParts));
        }
      }
      return rows;
    }

    return [
      {
        kind: "change",
        path: pathString(parts) || "",
        pathParts: parts.slice(),
        leftValue: left,
        rightValue: right,
      },
    ];
  }

  function setAtPath(root, pathOrParts, value) {
    const segments = resolvePathParts(pathOrParts);
    if (segments.length === 0) return cloneValue(value);

    const result = cloneValue(root);
    let cursor = result;
    for (let i = 0; i < segments.length - 1; i += 1) {
      const seg = segments[i];
      cursor = cursor[seg.value];
    }
    const last = segments[segments.length - 1];
    cursor[last.value] = cloneValue(value);
    return result;
  }

  function removeAtPath(root, pathOrParts) {
    const segments = resolvePathParts(pathOrParts);
    if (segments.length === 0) return root;

    const result = cloneValue(root);
    let cursor = result;
    for (let i = 0; i < segments.length - 1; i += 1) {
      const seg = segments[i];
      cursor = cursor[seg.value];
    }
    const last = segments[segments.length - 1];
    if (last.type === "index") {
      if (Array.isArray(cursor)) {
        cursor.splice(last.value, 1);
      }
    } else if (isPlainObject(cursor)) {
      delete cursor[last.value];
    }
    return result;
  }

  function rowPathRef(row) {
    return row.pathParts || row.path;
  }

  function applyRowToTarget(row, targetIsLeft, left, right) {
    const targetRoot = targetIsLeft ? left : right;
    const pathRef = rowPathRef(row);
    if (row.kind === "add") {
      if (targetIsLeft) {
        if (row.rightValue === undefined) return cloneValue(targetRoot);
        return setAtPath(targetRoot, pathRef, row.rightValue);
      }
      return removeAtPath(targetRoot, pathRef);
    }
    if (row.kind === "remove") {
      if (targetIsLeft) {
        return removeAtPath(targetRoot, pathRef);
      }
      if (row.leftValue === undefined) return cloneValue(targetRoot);
      return setAtPath(targetRoot, pathRef, row.leftValue);
    }
    // change
    if (targetIsLeft) {
      if (row.rightValue === undefined) return cloneValue(targetRoot);
      return setAtPath(targetRoot, pathRef, row.rightValue);
    }
    if (row.leftValue === undefined) return cloneValue(targetRoot);
    return setAtPath(targetRoot, pathRef, row.leftValue);
  }

  function sortRowsForApply(rows) {
    return rows.slice().sort((lhs, rhs) => {
      const leftDepth = lhs.path ? String(lhs.path).split(".").length : 0;
      const rightDepth = rhs.path ? String(rhs.path).split(".").length : 0;
      if (leftDepth !== rightDepth) return rightDepth - leftDepth;
      if (String(lhs.path) > String(rhs.path)) return -1;
      if (String(lhs.path) < String(rhs.path)) return 1;
      return 0;
    });
  }

  function apply(row, direction, leftRoot, rightRoot) {
    if (direction === "toLeft") {
      return {
        left: applyRowToTarget(row, true, leftRoot, rightRoot),
        right: cloneValue(rightRoot),
      };
    }
    return {
      left: cloneValue(leftRoot),
      right: applyRowToTarget(row, false, leftRoot, rightRoot),
    };
  }

  function applyAll(rows, direction, leftRoot, rightRoot) {
    const ordered = sortRowsForApply(rows);
    let currentLeft = cloneValue(leftRoot);
    let currentRight = cloneValue(rightRoot);
    for (const row of ordered) {
      const result = apply(row, direction, currentLeft, currentRight);
      currentLeft = result.left;
      currentRight = result.right;
    }
    return { left: currentLeft, right: currentRight };
  }

  function compare(leftText, rightText, indentKey) {
    const leftRoot = parseSide(leftText, "left");
    const rightRoot = parseSide(rightText, "right");
    const rows = structuredDiff(leftRoot, rightRoot, []);
    const core = global.DotJSONCore;
    const leftPretty = core
      ? core.format(JSON.stringify(leftRoot), indentKey)
      : JSON.stringify(leftRoot, null, 2);
    const rightPretty = core
      ? core.format(JSON.stringify(rightRoot), indentKey)
      : JSON.stringify(rightRoot, null, 2);
    const combinedSize = utf8ByteLength(leftText) + utf8ByteLength(rightText);
    let lineDiff;
    if (combinedSize > SOFT_INPUT_BYTE_LIMIT) {
      lineDiff = {
        kind: "skipped",
        message: "Combined input exceeds 2 MB; line diff omitted.",
      };
    } else {
      lineDiff = { kind: "available", rows: [] };
    }
    return {
      rows,
      leftPretty,
      rightPretty,
      leftRoot,
      rightRoot,
      lineDiff,
    };
  }

  global.DotJSONDiff = {
    SOFT_INPUT_BYTE_LIMIT,
    compare,
    apply,
    applyAll,
    pathString,
  };
})(typeof window !== "undefined" ? window : globalThis);
