import Foundation

private struct ToolDefinition {
    let name: String
    let description: String
    let inputSchema: [String: Any]
    var annotations: [String: Any]?
}

nonisolated(unsafe) private let readOnlyAnnotation: [String: Any] = [
    "readOnlyHint": true, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false
]
nonisolated(unsafe) private let mutatingAnnotation: [String: Any] = [
    "readOnlyHint": false, "destructiveHint": false, "idempotentHint": false, "openWorldHint": false
]
nonisolated(unsafe) private let destructiveAnnotation: [String: Any] = [
    "readOnlyHint": false, "destructiveHint": true, "idempotentHint": false, "openWorldHint": false
]

private enum MCPError: Error, CustomStringConvertible {
    case invalidRequest(String)
    case methodNotFound(String)
    case invalidParams(String)
    case toolNotFound(String)
    case toolError(String)
    case scriptError(String)

    var description: String {
        switch self {
        case .invalidRequest(let message):
            return message
        case .methodNotFound(let message):
            return message
        case .invalidParams(let message):
            return message
        case .toolNotFound(let name):
            return "Unknown tool: \(name)"
        case .toolError(let message):
            return message
        case .scriptError(let message):
            return message
        }
    }
}

private let jxaScript = #"""
ObjC.import('Foundation');

function env(name) {
  var value = $.NSProcessInfo.processInfo.environment.objectForKey(name);
  if (!value) {
    return null;
  }
  return ObjC.unwrap(value);
}

function toISO(date) {
  if (!date) {
    return null;
  }
  if (date instanceof Date) {
    return date.toISOString();
  }
  return null;
}

function safeCall(obj, prop) {
  try {
    if (typeof obj[prop] === 'function') {
      return obj[prop]();
    }
    if (obj[prop] !== undefined) {
      return obj[prop];
    }
  } catch (e) {
  }
  return null;
}

function safeSet(obj, prop, value) {
  try {
    obj[prop] = value;
    return true;
  } catch (e) {
  }
  return false;
}

function firstValue(obj, names) {
  for (var i = 0; i < names.length; i++) {
    var value = safeCall(obj, names[i]);
    if (value !== null && value !== undefined) {
      return value;
    }
  }
  return null;
}

function normalizeId(value) {
  if (value === null || value === undefined) {
    return null;
  }
  var id = String(value);
  var match = id.match(/^(.+)\.(\d+)$/);
  if (match && match[1] && match[1].length > 6) {
    return match[1];
  }
  return id;
}

function normalizeStatus(value) {
  if (!value) {
    return null;
  }
  var status = String(value).toLowerCase();
  if (status.indexOf('active') !== -1) {
    return 'active';
  }
  if (status.indexOf('done') !== -1 || status.indexOf('completed') !== -1) {
    return 'done';
  }
  if (status.indexOf('dropped') !== -1) {
    return 'dropped';
  }
  if (status.indexOf('on hold') !== -1 || status.indexOf('hold') !== -1 || status.indexOf('paused') !== -1) {
    return 'on_hold';
  }
  return String(value);
}

function arrayify(value) {
  if (!value) {
    return [];
  }
  if (Array.isArray(value)) {
    return value;
  }
  if (value.length !== undefined) {
    var result = [];
    for (var i = 0; i < value.length; i++) {
      result.push(value[i]);
    }
    return result;
  }
  return [value];
}

function uniqueById(items) {
  var indexByKey = {};
  var result = [];
  arrayify(items).forEach(function(item) {
    var key = normalizeId(safeCall(item, 'id')) || safeCall(item, 'name');
    if (!key) {
      key = String(result.length);
    }
    if (indexByKey[key] === undefined) {
      indexByKey[key] = result.length;
      result.push(item);
      return;
    }
    var existingIndex = indexByKey[key];
    var existing = result[existingIndex];
    var existingCompleted = !!safeCall(existing, 'completed');
    var candidateCompleted = !!safeCall(item, 'completed');
    if (existingCompleted && !candidateCompleted) {
      result[existingIndex] = item;
    }
  });
  return result;
}

function dateValue(value) {
  if (!value) {
    return null;
  }
  if (value instanceof Date) {
    return value;
  }
  var date = new Date(value);
  if (isNaN(date.getTime())) {
    return null;
  }
  return date;
}

function isTaskAvailable(task) {
  var available = safeCall(task, 'available');
  if (available !== null && available !== undefined) {
    return !!available;
  }
  var deferDate = dateValue(firstValue(task, ['deferDate']));
  if (!deferDate) {
    return true;
  }
  return deferDate.getTime() <= Date.now();
}

function isTaskOverdue(task) {
  var dueDate = dateValue(firstValue(task, ['dueDate']));
  if (!dueDate) {
    return false;
  }
  return dueDate.getTime() < Date.now();
}

function readInput() {
  var raw = env('OF_INPUT_JSON');
  if (!raw) {
    throw new Error('Missing OF_INPUT_JSON');
  }
  return JSON.parse(raw);
}

function getApp() {
  var appPath = env('OF_APP_PATH');
  if (!appPath) {
    appPath = '/Applications/OmniFocus.app';
  }
  var app = Application(appPath);
  app.launch();
  return app;
}

function getDocument() {
  var of = getApp();
  return of.defaultDocument();
}

function tagNames(task) {
  var tags = safeCall(task, 'tags');
  if (!tags) {
    tags = safeCall(task, 'contexts');
  }
  return arrayify(tags).map(function(tag) {
    return safeCall(tag, 'name');
  }).filter(function(name) { return name; });
}

function projectName(task) {
  var project = firstValue(task, ['containingProject', 'project']);
  if (!project) {
    return null;
  }
  return safeCall(project, 'name');
}

function appendNote(task, appendText) {
  if (!appendText) {
    return;
  }
  var existing = safeCall(task, 'note') || '';
  var separator = existing ? '\n' : '';
  safeSet(task, 'note', existing + separator + appendText);
}

function normalizeTaskStatus(ts) {
  if (ts === null || ts === undefined) { return null; }
  var s = String(ts).toLowerCase();
  if (s.indexOf('available') !== -1) { return 'available'; }
  if (s.indexOf('completed') !== -1) { return 'completed'; }
  if (s.indexOf('dropped') !== -1) { return 'dropped'; }
  if (s.indexOf('blocked') !== -1) { return 'blocked'; }
  if (s.indexOf('dueSoon') !== -1 || s.indexOf('duesoon') !== -1) { return 'dueSoon'; }
  if (s.indexOf('next') !== -1) { return 'next'; }
  if (s.indexOf('overdue') !== -1) { return 'overdue'; }
  return s;
}

function taskToJSON(task) {
  var ts = firstValue(task, ['taskStatus']);
  return {
    id: normalizeId(safeCall(task, 'id')),
    name: safeCall(task, 'name'),
    note: safeCall(task, 'note'),
    flagged: safeCall(task, 'flagged'),
    completed: safeCall(task, 'completed'),
    completionDate: toISO(firstValue(task, ['completionDate'])),
    dueDate: toISO(firstValue(task, ['dueDate'])),
    deferDate: toISO(firstValue(task, ['deferDate'])),
    plannedDate: toISO(firstValue(task, ['plannedDate'])),
    effectivePlannedDate: toISO(firstValue(task, ['effectivePlannedDate'])),
    effectiveDueDate: toISO(firstValue(task, ['effectiveDueDate'])),
    effectiveDeferDate: toISO(firstValue(task, ['effectiveDeferDate'])),
    effectiveFlagged: safeCall(task, 'effectiveFlagged'),
    added: toISO(firstValue(task, ['added', 'dateAdded'])),
    modified: toISO(firstValue(task, ['modified', 'dateModified'])),
    taskStatus: normalizeTaskStatus(ts),
    sequential: safeCall(task, 'sequential'),
    completedByChildren: safeCall(task, 'completedByChildren'),
    hasChildren: safeCall(task, 'hasChildren'),
    url: null,
    estimatedMinutes: safeCall(task, 'estimatedMinutes'),
    dropDate: toISO(firstValue(task, ['dropDate'])),
    effectiveCompletedDate: toISO(firstValue(task, ['effectiveCompletedDate'])),
    effectiveDropDate: toISO(firstValue(task, ['effectiveDropDate'])),
    shouldUseFloatingTimeZone: safeCall(task, 'shouldUseFloatingTimeZone'),
    assignedContainer: (function() {
      try {
        var ac = firstValue(task, ['assignedContainer']);
        if (!ac) return null;
        return {id: normalizeId(safeCall(ac, 'id')), name: safeCall(ac, 'name')};
      } catch (e) { return null; }
    })(),
    tags: tagNames(task),
    project: projectName(task),
    inbox: safeCall(task, 'inInbox')
  };
}

function projectToJSON(project) {
  var status = firstValue(project, ['status', 'projectStatus']);
  var rawStatus = status ? String(status) : null;
  var ri = null;
  try {
    var riObj = safeCall(project, 'reviewInterval');
    if (riObj) {
      ri = {steps: safeCall(riObj, 'steps'), unit: String(safeCall(riObj, 'unit') || '')};
    }
  } catch (e) {}
  var pf = safeCall(project, 'folder');
  var pfName = pf ? safeCall(pf, 'name') : null;
  var pfId = pf ? normalizeId(safeCall(pf, 'id')) : null;
  var ntasks = null;
  var navail = null;
  try {
    var ft = arrayify(firstValue(project, ['flattenedTasks', 'tasks']));
    ntasks = ft.length;
    var ac = 0;
    for (var ti = 0; ti < ft.length; ti++) {
      if (!safeCall(ft[ti], 'completed') && !safeCall(ft[ti], 'dropped')) { ac++; }
    }
    navail = ac;
  } catch (e) {}
  return {
    id: normalizeId(safeCall(project, 'id')),
    name: safeCall(project, 'name'),
    note: safeCall(project, 'note'),
    status: normalizeStatus(rawStatus),
    statusRaw: rawStatus,
    completed: safeCall(project, 'completed'),
    completionDate: toISO(firstValue(project, ['completionDate'])),
    dueDate: toISO(firstValue(project, ['dueDate'])),
    deferDate: toISO(firstValue(project, ['deferDate'])),
    flagged: safeCall(project, 'flagged'),
    sequential: !safeCall(project, 'parallel'),
    containsSingletonActions: safeCall(project, 'containsSingletonActions'),
    estimatedMinutes: safeCall(project, 'estimatedMinutes'),
    lastReviewDate: toISO(firstValue(project, ['lastReviewDate'])),
    nextReviewDate: toISO(firstValue(project, ['nextReviewDate'])),
    reviewInterval: ri,
    parentFolder: pfName,
    parentFolderId: pfId,
    added: toISO(firstValue(project, ['added', 'dateAdded'])),
    modified: toISO(firstValue(project, ['modified', 'dateModified'])),
    numberOfTasks: ntasks,
    numberOfAvailableTasks: navail,
    effectiveDueDate: toISO(firstValue(project, ['effectiveDueDate'])),
    effectiveDeferDate: toISO(firstValue(project, ['effectiveDeferDate'])),
    effectiveFlagged: safeCall(project, 'effectiveFlagged'),
    url: null,
    nextTask: (function() {
      try {
        var nt = firstValue(project, ['nextTask']);
        if (!nt) return null;
        return {id: normalizeId(safeCall(nt, 'id')), name: safeCall(nt, 'name')};
      } catch (e) { return null; }
    })(),
    defaultSingletonActionHolder: safeCall(project, 'defaultSingletonActionHolder'),
    shouldUseFloatingTimeZone: safeCall(project, 'shouldUseFloatingTimeZone'),
    dropDate: toISO(firstValue(project, ['dropDate'])),
    effectiveCompletedDate: toISO(firstValue(project, ['effectiveCompletedDate'])),
    effectiveDropDate: toISO(firstValue(project, ['effectiveDropDate']))
  };
}

function getTagParent(tag) {
  // In JXA, try 'parent' first, then fall back to 'container'.
  // 'container' returns the parent tag for nested tags, or the document for top-level tags.
  var p = safeCall(tag, 'parent');
  if (p && safeCall(p, 'name')) { return p; }
  var c = safeCall(tag, 'container');
  // Only return if container is a tag (has 'name' and 'active' properties), not the document
  if (c && safeCall(c, 'name') && safeCall(c, 'active') !== null) { return c; }
  return null;
}

function tagToJSON(tag) {
  var parentTag = getTagParent(tag);
  var parentName = null;
  var parentId = null;
  if (parentTag) {
    parentName = safeCall(parentTag, 'name');
    parentId = normalizeId(safeCall(parentTag, 'id'));
  }
  var ts = firstValue(tag, ['status']);
  return {
    id: normalizeId(safeCall(tag, 'id')),
    name: safeCall(tag, 'name'),
    parent: parentName,
    parentId: parentId,
    active: safeCall(tag, 'active'),
    status: ts !== null && ts !== undefined ? String(ts) : null,
    allowsNextAction: safeCall(tag, 'allowsNextAction'),
    childrenAreMutuallyExclusive: safeCall(tag, 'childrenAreMutuallyExclusive'),
    availableTaskCount: (function() { try { return arrayify(safeCall(tag, 'availableTasks')).length; } catch (e) { return null; } })()
  };
}

function perspectiveToJSON(perspective) {
  var identifier = safeCall(perspective, 'id');
  if (!identifier) {
    identifier = safeCall(perspective, 'identifier');
  }
  var afr = null;
  try { afr = safeCall(perspective, 'archivedFilterRules'); } catch (e) {}
  var ic = null;
  try { ic = safeCall(perspective, 'iconColor'); } catch (e) {}
  return {
    id: normalizeId(identifier),
    name: safeCall(perspective, 'name'),
    archivedFilterRules: afr,
    iconColor: ic
  };
}

function folderToJSON(folder) {
  var fc = safeCall(folder, 'container');
  var fpName = null;
  var fpId = null;
  // Only treat container as parent folder if it's actually a folder (not the document).
  // The document has no container of its own, so check for that.
  if (fc && safeCall(fc, 'name') && safeCall(fc, 'id')) {
    var fcContainer = safeCall(fc, 'container');
    if (fcContainer !== null && fcContainer !== undefined) {
      fpName = safeCall(fc, 'name');
      fpId = normalizeId(safeCall(fc, 'id'));
    }
  }
  var ts = firstValue(folder, ['status']);
  return {
    id: normalizeId(safeCall(folder, 'id')),
    name: safeCall(folder, 'name'),
    note: safeCall(folder, 'note'),
    status: ts !== null && ts !== undefined ? String(ts) : null,
    parentId: fpId,
    parentName: fpName,
    projectCount: arrayify(safeCall(folder, 'projects')).length,
    folderCount: arrayify(safeCall(folder, 'folders')).length
  };
}

function collectFoldersFrom(container, result, seen) {
  var folders = arrayify(firstValue(container, ['folders']));
  for (var i = 0; i < folders.length; i++) {
    var folder = folders[i];
    var key = normalizeId(safeCall(folder, 'id')) || safeCall(folder, 'name') || String(result.length);
    if (!seen[key]) {
      seen[key] = true;
      result.push(folder);
      collectFoldersFrom(folder, result, seen);
    }
  }
}

function allFolders(doc) {
  var flattened = firstValue(doc, ['flattenedFolders', 'folders']);
  var list = arrayify(flattened);
  if (list.length > 0) {
    return list;
  }
  var result = [];
  collectFoldersFrom(doc, result, {});
  return result;
}

function findFolderByName(doc, name) {
  var folders = allFolders(doc);
  for (var i = 0; i < folders.length; i++) {
    if (safeCall(folders[i], 'name') === name) {
      return folders[i];
    }
  }
  return null;
}

function findFolderById(doc, id) {
  var folders = allFolders(doc);
  for (var i = 0; i < folders.length; i++) {
    if (normalizeId(safeCall(folders[i], 'id')) === normalizeId(id)) {
      return folders[i];
    }
  }
  return null;
}

function findProjectByName(doc, name) {
  var projects = arrayify(firstValue(doc, ['flattenedProjects', 'projects']));
  for (var i = 0; i < projects.length; i++) {
    if (safeCall(projects[i], 'name') === name) {
      return projects[i];
    }
  }
  return null;
}

function findProjectById(doc, id) {
  var projects = arrayify(firstValue(doc, ['flattenedProjects', 'projects']));
  for (var i = 0; i < projects.length; i++) {
    if (normalizeId(safeCall(projects[i], 'id')) === normalizeId(id)) {
      return projects[i];
    }
  }
  return null;
}

function findTagByName(doc, name) {
  // Support "Parent > Child" syntax for disambiguation
  var parts = name.split(' > ');
  if (parts.length === 2) {
    var parentName = parts[0].trim();
    var childName = parts[1].trim();
    if (!parentName || !childName) { return null; }
    var tags = arrayify(firstValue(doc, ['flattenedTags', 'tags', 'contexts']));
    for (var i = 0; i < tags.length; i++) {
      if (safeCall(tags[i], 'name') === childName) {
        var parent = getTagParent(tags[i]);
        if (parent && safeCall(parent, 'name') === parentName) {
          return tags[i];
        }
      }
    }
    return null;
  }
  var tags = arrayify(firstValue(doc, ['flattenedTags', 'tags', 'contexts']));
  for (var i = 0; i < tags.length; i++) {
    if (safeCall(tags[i], 'name') === name) {
      return tags[i];
    }
  }
  return null;
}

function findTagById(doc, id) {
  var tags = arrayify(firstValue(doc, ['flattenedTags', 'tags', 'contexts']));
  for (var i = 0; i < tags.length; i++) {
    if (normalizeId(safeCall(tags[i], 'id')) === normalizeId(id)) {
      return tags[i];
    }
  }
  return null;
}

function ensureTag(doc, name, createMissing) {
  var tag = findTagByName(doc, name);
  if (!tag && createMissing) {
    var parts = name.split(' > ');
    if (parts.length === 2) {
      var parentName = parts[0].trim();
      var childName = parts[1].trim();
      if (!parentName || !childName) { return doc.make({new: 'tag', withProperties: {name: name}}); }
      var parentTag = findTagByName(doc, parentName);
      if (!parentTag) {
        parentTag = doc.make({new: 'tag', withProperties: {name: parentName}});
      }
      if (parentTag) {
        try { tag = doc.make({new: 'tag', withProperties: {name: childName}, at: parentTag.tags.end}); } catch (e) {}
      }
      // Do NOT fall back to creating a root-level tag — that creates duplicates
    } else {
      tag = doc.make({new: 'tag', withProperties: {name: name}});
    }
  }
  return tag;
}

function resolveTags(doc, names, createMissing) {
  var result = [];
  arrayify(names).forEach(function(name) {
    if (!name) {
      return;
    }
    var tag = ensureTag(doc, name, createMissing);
    if (tag) {
      result.push(tag);
    }
  });
  return result;
}

function findTaskById(doc, id) {
  var tasks = arrayify(firstValue(doc, ['flattenedTasks', 'tasks']));
  for (var i = 0; i < tasks.length; i++) {
    if (normalizeId(safeCall(tasks[i], 'id')) === normalizeId(id)) {
      return tasks[i];
    }
  }
  return null;
}

function parseDate(value) {
  if (!value) {
    return null;
  }
  // Date-only strings (YYYY-MM-DD) are parsed as UTC midnight by the JS spec,
  // which shifts the displayed date by one day in negative-offset timezones.
  // Construct with integer args instead so the result is local midnight,
  // giving the correct calendar date regardless of where the user is.
  var dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
  if (dateOnly) {
    var d = new Date(parseInt(dateOnly[1]), parseInt(dateOnly[2]) - 1, parseInt(dateOnly[3]));
    return isNaN(d.getTime()) ? null : d;
  }
  var date = new Date(value);
  if (isNaN(date.getTime())) {
    return null;
  }
  return date;
}

function applyCommonTaskFields(task, params, doc) {
  if (params.name !== undefined) {
    task.name = params.name;
  }
  if (params.note !== undefined) {
    task.note = params.note;
  }
  if (params.flagged !== undefined) {
    task.flagged = params.flagged;
  }
  if (params.estimatedMinutes !== undefined) {
    task.estimatedMinutes = params.estimatedMinutes;
  }
  var due = parseDate(params.due);
  if (due) {
    task.dueDate = due;
  }
  if (params.due === null) {
    task.dueDate = null;
  }
  var deferDate = parseDate(params.defer);
  if (deferDate) {
    task.deferDate = deferDate;
  }
  if (params.defer === null) {
    task.deferDate = null;
  }
  if (params.planned !== undefined) {
    var pd = parseDate(params.planned);
    if (pd) { safeSet(task, 'plannedDate', pd); }
    if (params.planned === null) { safeSet(task, 'plannedDate', null); }
  }
  if (params.sequential !== undefined) {
    safeSet(task, 'sequential', params.sequential);
  }
  if (params.completedByChildren !== undefined) {
    safeSet(task, 'completedByChildren', params.completedByChildren);
  }
  if (params.shouldUseFloatingTimeZone !== undefined) {
    safeSet(task, 'shouldUseFloatingTimeZone', params.shouldUseFloatingTimeZone);
  }
  if (params.tags !== undefined) {
    var tagObjects = resolveTags(doc, params.tags, params.createMissingTags === true);
    task.tags = tagObjects;
  }
}

function markTaskComplete(task, completionDate) {
  var date = parseDate(completionDate);
  var marked = false;
  try {
    if (typeof task.markComplete === 'function') {
      task.markComplete();
      marked = true;
    }
  } catch (e) {
  }
  if (!marked) {
    try {
      task.completed = true;
      marked = true;
    } catch (e) {
    }
  }
  if (date) {
    try {
      task.completionDate = date;
    } catch (e) {
    }
  }
}

function listTasks(params) {
  var doc = getDocument();
  var tasks = arrayify(firstValue(doc, ['flattenedTasks', 'tasks']));
  var status = params.status || 'all';
  var projectFilter = params.project || null;
  var tagFilter = params.tag || null;
  var search = params.search ? params.search.toLowerCase() : null;
  var flaggedFilter = params.flagged;
  var limit = params.limit || null;

  var result = [];
  for (var i = 0; i < tasks.length; i++) {
    var task = tasks[i];
    var completed = !!safeCall(task, 'completed');
    if (status === 'completed' && !completed) {
      continue;
    }
    if (status === 'available' && completed) {
      continue;
    }
    if (status === 'available' && !isTaskAvailable(task)) {
      continue;
    }
    if (projectFilter) {
      var projectNameValue = projectName(task);
      if (projectNameValue !== projectFilter) {
        continue;
      }
    }
    if (tagFilter) {
      var tags = tagNames(task);
      if (tags.indexOf(tagFilter) === -1) {
        continue;
      }
    }
    if (search) {
      var name = safeCall(task, 'name') || '';
      var note = safeCall(task, 'note') || '';
      var haystack = (name + ' ' + note).toLowerCase();
      if (haystack.indexOf(search) === -1) {
        continue;
      }
    }
    if (flaggedFilter !== undefined) {
      var flagged = !!safeCall(task, 'flagged');
      if (flagged !== !!flaggedFilter) {
        continue;
      }
    }
    result.push(taskToJSON(task));
    if (limit && result.length >= limit) {
      break;
    }
  }
  return result;
}

function listInbox() {
  var doc = getDocument();
  var inbox = firstValue(doc, ['inboxTasks', 'inbox']);
  var tasks = arrayify(inbox);
  return tasks.map(taskToJSON);
}

function listProjects() {
  var doc = getDocument();
  var projects = uniqueById(firstValue(doc, ['flattenedProjects', 'projects']));
  return projects.map(projectToJSON);
}

function listTags() {
  var doc = getDocument();
  var tags = uniqueById(firstValue(doc, ['flattenedTags', 'tags', 'contexts']));
  return tags.map(tagToJSON);
}

function listPerspectives() {
  var app = getApp();
  var perspectives = arrayify(firstValue(app, ['perspectives']));
  return perspectives.map(perspectiveToJSON);
}

function listFolders() {
  var doc = getDocument();
  var folders = allFolders(doc);
  return folders.map(folderToJSON);
}

function createFolder(params) {
  var doc = getDocument();
  var parent = null;
  if (params.parentId) {
    parent = findFolderById(doc, params.parentId);
  } else if (params.parent) {
    parent = findFolderByName(doc, params.parent);
  }
  if (params.parent && !parent) {
    throw new Error('Parent folder not found');
  }
  var properties = {name: params.name};
  if (params.note !== undefined) {
    properties.note = params.note;
  }
  var folder = null;
  if (parent && typeof parent.make === 'function') {
    folder = parent.make({new: 'folder', withProperties: properties});
  }
  if (!folder) {
    folder = doc.make({new: 'folder', withProperties: properties});
  }
  if (parent && folder) {
    safeSet(folder, 'containingFolder', parent);
  }
  if (!folder) {
    throw new Error('Unable to create folder');
  }
  return folderToJSON(folder);
}

function moveProject(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.projectId);
  if (!project) {
    throw new Error('Project not found');
  }
  var target = null;
  if (params.folderId) {
    target = findFolderById(doc, params.folderId);
  } else if (params.folder) {
    target = findFolderByName(doc, params.folder);
  }
  if ((params.folderId || params.folder) && !target) {
    if (params.createMissingFolder === true && params.folder) {
      var created = createFolder({name: params.folder});
      if (created && created.id) {
        target = findFolderById(doc, created.id);
      }
      if (!target) {
        target = findFolderByName(doc, params.folder);
      }
    } else {
      throw new Error('Folder not found');
    }
  }
  var app = getApp();
  if (target) {
    app.move(project, {to: target.projects.end});
  } else {
    app.move(project, {to: doc.projects.end});
  }
  return projectToJSON(project);
}

function listFlagged(params) {
  var query = params || {};
  query.flagged = true;
  return listTasks(query);
}

function listOverdue(params) {
  var doc = getDocument();
  var tasks = arrayify(firstValue(doc, ['flattenedTasks', 'tasks']));
  var includeCompleted = params.includeCompleted === true;
  var limit = params.limit || null;
  var result = [];
  for (var i = 0; i < tasks.length; i++) {
    var task = tasks[i];
    if (!includeCompleted && !!safeCall(task, 'completed')) {
      continue;
    }
    if (!isTaskOverdue(task)) {
      continue;
    }
    result.push(taskToJSON(task));
    if (limit && result.length >= limit) {
      break;
    }
  }
  return result;
}

function listAvailable(params) {
  var doc = getDocument();
  var tasks = arrayify(firstValue(doc, ['flattenedTasks', 'tasks']));
  var includeCompleted = params.includeCompleted === true;
  var limit = params.limit || null;
  var result = [];
  for (var i = 0; i < tasks.length; i++) {
    var task = tasks[i];
    if (!includeCompleted && !!safeCall(task, 'completed')) {
      continue;
    }
    if (!isTaskAvailable(task)) {
      continue;
    }
    result.push(taskToJSON(task));
    if (limit && result.length >= limit) {
      break;
    }
  }
  return result;
}

function searchTasks(params) {
  return listTasks(params);
}

function listTaskChildren(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) {
    throw new Error('Task not found');
  }
  var children = firstValue(task, ['tasks', 'subtasks', 'childTasks']);
  return arrayify(children).map(taskToJSON);
}

function getTaskParent(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) {
    throw new Error('Task not found');
  }
  var parent = firstValue(task, ['containingTask', 'parentTask']);
  if (!parent) {
    return null;
  }
  return taskToJSON(parent);
}

function getTask(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) {
    throw new Error('Task not found');
  }
  return taskToJSON(task);
}

function getProject(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) {
    throw new Error('Project not found');
  }
  return projectToJSON(project);
}

function getTag(params) {
  var doc = getDocument();
  var tag = findTagById(doc, params.id);
  if (!tag) {
    throw new Error('Tag not found');
  }
  return tagToJSON(tag);
}

function createTask(params) {
  var doc = getDocument();
  var projectNameValue = params.project || null;
  var createMissingProject = params.createMissingProject === true;
  var project = null;
  if (projectNameValue && !params.inbox) {
    project = findProjectByName(doc, projectNameValue);
    if (!project && createMissingProject) {
      project = doc.make({new: 'project', withProperties: {name: projectNameValue}});
    }
    if (!project) {
      throw new Error('Project not found');
    }
  }
  var properties = {
    name: params.name
  };
  if (params.note !== undefined) {
    properties.note = params.note;
  }
  if (params.flagged !== undefined) {
    properties.flagged = params.flagged;
  }
  if (params.estimatedMinutes !== undefined) {
    properties.estimatedMinutes = params.estimatedMinutes;
  }
  var due = parseDate(params.due);
  if (due) {
    properties.dueDate = due;
  }
  var deferDate = parseDate(params.defer);
  if (deferDate) {
    properties.deferDate = deferDate;
  }

  var task = null;
  if (project) {
    task = project.make({new: 'task', withProperties: properties});
  } else {
    task = doc.make({new: 'inbox task', withProperties: properties});
  }

  if (params.tags !== undefined) {
    var tagObjects = resolveTags(doc, params.tags, params.createMissingTags === true);
    task.tags = tagObjects;
  }
  return taskToJSON(task);
}

function createProject(params) {
  var doc = getDocument();
  var properties = {
    name: params.name
  };
  if (params.note !== undefined) {
    properties.note = params.note;
  }
  if (params.flagged !== undefined) {
    properties.flagged = params.flagged;
  }
  var due = parseDate(params.due);
  if (due) {
    properties.dueDate = due;
  }
  var deferDate = parseDate(params.defer);
  if (deferDate) {
    properties.deferDate = deferDate;
  }

  var app = getApp();
  var project = app.make({new: 'project', withProperties: properties, at: doc.projects.end});
  return projectToJSON(project);
}

function createTag(params) {
  var doc = getDocument();
  var properties = {
    name: params.name
  };
  if (params.active !== undefined) {
    properties.active = params.active;
  }
  var tag = doc.make({new: 'tag', withProperties: properties});
  return tagToJSON(tag);
}

function updateTask(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) {
    throw new Error('Task not found');
  }
  applyCommonTaskFields(task, params, doc);
  if (params.project !== undefined) {
    var project = null;
    if (params.project) {
      project = findProjectByName(doc, params.project);
      if (!project && params.createMissingProject === true) {
        project = doc.make({new: 'project', withProperties: {name: params.project}});
      }
      if (!project) {
        throw new Error('Project not found');
      }
      try {
        project.tasks.push(task);
      } catch (e) {
        try {
          task.project = project;
        } catch (e2) {
          throw new Error('Unable to move task to project');
        }
      }
    } else {
      try {
        task.inInbox = true;
      } catch (e3) {
      }
    }
  }
  return taskToJSON(task);
}

function setProjectSequential(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) {
    throw new Error('Project not found');
  }
  var sequential = params.sequential === true;
  var applied = false;
  try {
    project.sequential = sequential;
    applied = true;
  } catch (e) {
  }
  if (!applied) {
    try {
      project.parallel = !sequential;
      applied = true;
    } catch (e2) {
    }
  }
  if (!applied) {
    throw new Error('Unable to update project sequencing');
  }
  return projectToJSON(project);
}

function processInbox(params) {
  var doc = getDocument();
  var inbox = arrayify(firstValue(doc, ['inboxTasks', 'inbox']));
  var limit = params.limit || null;
  var project = null;
  if (params.projectId) {
    project = findProjectById(doc, params.projectId);
  } else if (params.project) {
    project = findProjectByName(doc, params.project);
    if (!project && params.createMissingProject === true) {
      project = doc.make({new: 'project', withProperties: {name: params.project}});
    }
  }
  if ((params.projectId || params.project) && !project) {
    throw new Error('Project not found');
  }
  var tagObjects = null;
  if (params.tags !== undefined) {
    tagObjects = resolveTags(doc, params.tags, params.createMissingTags === true);
  }
  var result = [];
  for (var i = 0; i < inbox.length; i++) {
    var task = inbox[i];
    if (params.flagged !== undefined) {
      safeSet(task, 'flagged', params.flagged);
    }
    if (params.estimatedMinutes !== undefined) {
      safeSet(task, 'estimatedMinutes', params.estimatedMinutes);
    }
    var due = parseDate(params.due);
    if (due) {
      safeSet(task, 'dueDate', due);
    }
    if (params.due === null) {
      safeSet(task, 'dueDate', null);
    }
    var deferDate = parseDate(params.defer);
    if (deferDate) {
      safeSet(task, 'deferDate', deferDate);
    }
    if (params.defer === null) {
      safeSet(task, 'deferDate', null);
    }
    if (tagObjects) {
      task.tags = tagObjects;
    }
    if (params.noteAppend) {
      appendNote(task, params.noteAppend);
    }
    if (project && params.keepInInbox !== true) {
      try {
        project.tasks.push(task);
      } catch (e) {
        try {
          task.project = project;
        } catch (e2) {
        }
      }
    }
    result.push(taskToJSON(task));
    if (limit && result.length >= limit) {
      break;
    }
  }
  return result;
}

function applyCommonProjectFields(project, params) {
  if (params.name !== undefined) {
    project.name = params.name;
  }
  if (params.note !== undefined) {
    project.note = params.note;
  }
  if (params.flagged !== undefined) {
    project.flagged = params.flagged;
  }
  var due = parseDate(params.due);
  if (due) {
    project.dueDate = due;
  }
  if (params.due === null) {
    project.dueDate = null;
  }
  var deferDate = parseDate(params.defer);
  if (deferDate) {
    project.deferDate = deferDate;
  }
  if (params.defer === null) {
    project.deferDate = null;
  }
  if (params.estimatedMinutes !== undefined) {
    safeSet(project, 'estimatedMinutes', params.estimatedMinutes);
  }
  if (params.sequential !== undefined) {
    safeSet(project, 'parallel', !params.sequential);
  }
  if (params.containsSingletonActions !== undefined) {
    safeSet(project, 'containsSingletonActions', params.containsSingletonActions);
  }
  if (params.reviewInterval !== undefined && params.reviewInterval) {
    try {
      var ri = safeCall(project, 'reviewInterval');
      if (ri) {
        safeSet(ri, 'steps', params.reviewInterval.steps || 1);
        safeSet(ri, 'unit', params.reviewInterval.unit || 'weeks');
      }
    } catch (e) {}
  }
  if (params.shouldUseFloatingTimeZone !== undefined) {
    safeSet(project, 'shouldUseFloatingTimeZone', params.shouldUseFloatingTimeZone);
  }
}

function updateProject(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) {
    throw new Error('Project not found');
  }
  applyCommonProjectFields(project, params);
  return projectToJSON(project);
}

function updateTag(params) {
  var doc = getDocument();
  var tag = findTagById(doc, params.id);
  if (!tag) {
    throw new Error('Tag not found');
  }
  if (params.name !== undefined) {
    tag.name = params.name;
  }
  if (params.active !== undefined) {
    tag.active = params.active;
  }
  if (params.allowsNextAction !== undefined) {
    safeSet(tag, 'allowsNextAction', params.allowsNextAction);
  }
  return tagToJSON(tag);
}

function completeTask(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) {
    throw new Error('Task not found');
  }
  markTaskComplete(task, params.completionDate || null);
  return taskToJSON(task);
}

function markProjectComplete(project, completionDate) {
  var date = parseDate(completionDate);
  var marked = false;
  try {
    if (typeof project.markComplete === 'function') {
      project.markComplete();
      marked = true;
    }
  } catch (e) {
  }
  if (!marked) {
    try {
      project.completed = true;
      marked = true;
    } catch (e) {
    }
  }
  if (date) {
    try {
      project.completionDate = date;
    } catch (e) {
    }
  }
}

function completeProject(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) {
    throw new Error('Project not found');
  }
  markProjectComplete(project, params.completionDate || null);
  return projectToJSON(project);
}

function deleteTask(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) {
    throw new Error('Task not found');
  }
  task.delete();
  return {id: params.id, deleted: true};
}

function deleteProject(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) {
    throw new Error('Project not found');
  }
  project.delete();
  return {id: params.id, deleted: true};
}

function deleteTag(params) {
  var doc = getDocument();
  var tag = findTagById(doc, params.id);
  if (!tag) {
    throw new Error('Tag not found');
  }
  tag.delete();
  return {id: params.id, deleted: true};
}

function uncompleteTask(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) {
    throw new Error('Task not found');
  }
  var marked = false;
  try {
    if (typeof task.markIncomplete === 'function') {
      task.markIncomplete();
      marked = true;
    }
  } catch (e) {}
  if (!marked) {
    try {
      task.completed = false;
    } catch (e) {}
  }
  return taskToJSON(task);
}

function uncompleteProject(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) {
    throw new Error('Project not found');
  }
  try {
    project.status = 'active project';
  } catch (e) {
    try {
      project.completed = false;
    } catch (e2) {}
  }
  return projectToJSON(project);
}

function appendToNote(params) {
  var doc = getDocument();
  var obj = null;
  if (params.type === 'project') {
    obj = findProjectById(doc, params.id);
    if (!obj) { throw new Error('Project not found'); }
    appendNote(obj, params.text);
    return projectToJSON(obj);
  } else {
    obj = findTaskById(doc, params.id);
    if (!obj) { throw new Error('Task not found'); }
    appendNote(obj, params.text);
    return taskToJSON(obj);
  }
}

function searchTags(params) {
  var doc = getDocument();
  var query = (params.query || '').toLowerCase();
  var tags = arrayify(firstValue(doc, ['flattenedTags', 'tags', 'contexts']));
  var result = [];
  for (var i = 0; i < tags.length; i++) {
    var name = (safeCall(tags[i], 'name') || '').toLowerCase();
    if (!query || name.indexOf(query) !== -1) {
      result.push(tagToJSON(tags[i]));
    }
  }
  return result;
}

function setProjectStatus(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) { throw new Error('Project not found'); }
  var statusMap = {'active': 'active', 'on_hold': 'on hold', 'dropped': 'dropped'};
  var jxaStatus = statusMap[params.status];
  if (!jxaStatus) { throw new Error('Invalid status: ' + params.status); }
  try {
    project.status = jxaStatus;
  } catch (e) {
    throw new Error('Unable to set project status');
  }
  return projectToJSON(project);
}

function getFolder(params) {
  var doc = getDocument();
  var folder = null;
  if (params.id) {
    folder = findFolderById(doc, params.id);
  } else if (params.name) {
    folder = findFolderByName(doc, params.name);
  }
  if (!folder) { throw new Error('Folder not found'); }
  var result = folderToJSON(folder);
  result.projects = arrayify(firstValue(folder, ['projects', 'flattenedProjects'])).map(function(p) {
    return safeCall(p, 'name');
  }).filter(function(n) { return n; });
  result.subfolders = arrayify(firstValue(folder, ['folders'])).map(function(f) {
    return safeCall(f, 'name');
  }).filter(function(n) { return n; });
  return result;
}

function updateFolder(params) {
  var doc = getDocument();
  var folder = findFolderById(doc, params.id);
  if (!folder) { throw new Error('Folder not found'); }
  if (params.name !== undefined) {
    folder.name = params.name;
  }
  return folderToJSON(folder);
}

function deleteFolder(params) {
  var doc = getDocument();
  var folder = findFolderById(doc, params.id);
  if (!folder) { throw new Error('Folder not found'); }
  var name = safeCall(folder, 'name');
  folder.delete();
  return {id: params.id, deleted: true, name: name};
}

function getTaskCounts(params) {
  var doc = getDocument();
  var tasks = arrayify(firstValue(doc, ['flattenedTasks', 'tasks']));
  var inbox = arrayify(firstValue(doc, ['inboxTasks', 'inbox']));
  var total = 0, available = 0, completed = 0, overdue = 0, flagged = 0;
  for (var i = 0; i < tasks.length; i++) {
    var task = tasks[i];
    total++;
    if (!!safeCall(task, 'completed')) { completed++; continue; }
    if (isTaskAvailable(task)) { available++; }
    if (isTaskOverdue(task)) { overdue++; }
    if (!!safeCall(task, 'flagged')) { flagged++; }
  }
  return {total: total, available: available, completed: completed, overdue: overdue, flagged: flagged, inbox: inbox.length};
}

function getProjectCounts(params) {
  var doc = getDocument();
  var projects = arrayify(firstValue(doc, ['flattenedProjects', 'projects']));
  var total = 0, active = 0, onHold = 0, dropped = 0, stalled = 0;
  for (var i = 0; i < projects.length; i++) {
    var project = projects[i];
    total++;
    var rawStatus = String(firstValue(project, ['status', 'projectStatus']) || '');
    var status = normalizeStatus(rawStatus);
    if (status === 'active') {
      active++;
      var ptasks = arrayify(firstValue(project, ['tasks', 'flattenedTasks']));
      var hasAvailable = false;
      for (var j = 0; j < ptasks.length; j++) {
        if (!safeCall(ptasks[j], 'completed') && isTaskAvailable(ptasks[j])) {
          hasAvailable = true;
          break;
        }
      }
      if (!hasAvailable) { stalled++; }
    } else if (status === 'dropped') {
      dropped++;
    } else if (status === 'on_hold') {
      onHold++;
    }
  }
  return {total: total, active: active, on_hold: onHold, dropped: dropped, stalled: stalled};
}

function getForecast(params) {
  var doc = getDocument();
  var tasks = arrayify(firstValue(doc, ['flattenedTasks', 'tasks']));
  var now = new Date();
  var todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
  var weekEnd = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
  var overdue = [], today = [], flagged = [], dueThisWeek = [];
  for (var i = 0; i < tasks.length; i++) {
    var task = tasks[i];
    if (!!safeCall(task, 'completed')) { continue; }
    var dueDate = dateValue(firstValue(task, ['dueDate']));
    if (dueDate) {
      if (dueDate.getTime() < now.getTime()) {
        overdue.push(taskToJSON(task));
      } else if (dueDate.getTime() <= todayEnd.getTime()) {
        today.push(taskToJSON(task));
      } else if (dueDate.getTime() <= weekEnd.getTime()) {
        dueThisWeek.push(taskToJSON(task));
      }
    }
    if (!!safeCall(task, 'flagged')) { flagged.push(taskToJSON(task)); }
  }
  return {overdue: overdue, today: today, flagged: flagged, dueThisWeek: dueThisWeek};
}

function createSubtask(params) {
  var doc = getDocument();
  var parent = findTaskById(doc, params.parentId);
  if (!parent) { throw new Error('Parent task not found'); }
  var properties = {name: params.name};
  if (params.note !== undefined) { properties.note = params.note; }
  if (params.flagged !== undefined) { properties.flagged = params.flagged; }
  if (params.estimatedMinutes !== undefined) { properties.estimatedMinutes = params.estimatedMinutes; }
  var due = parseDate(params.due);
  if (due) { properties.dueDate = due; }
  var deferDate = parseDate(params.defer);
  if (deferDate) { properties.deferDate = deferDate; }
  var task = parent.make({new: 'task', withProperties: properties});
  if (params.tags !== undefined) {
    var tagObjects = resolveTags(doc, params.tags, params.createMissingTags === true);
    task.tags = tagObjects;
  }
  return taskToJSON(task);
}

function duplicateTask(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var project = firstValue(task, ['containingProject', 'project']);
  var newParams = {
    name: params.name || safeCall(task, 'name'),
    note: safeCall(task, 'note'),
    flagged: safeCall(task, 'flagged'),
    due: toISO(firstValue(task, ['dueDate'])),
    defer: toISO(firstValue(task, ['deferDate'])),
    estimatedMinutes: safeCall(task, 'estimatedMinutes'),
    tags: tagNames(task),
    createMissingTags: false
  };
  if (project) {
    newParams.project = safeCall(project, 'name');
    newParams.createMissingProject = false;
  } else {
    newParams.inbox = true;
  }
  return createTask(newParams);
}

function createTasksBatch(params) {
  var tasks = params.tasks || [];
  var result = [];
  for (var i = 0; i < tasks.length; i++) {
    result.push(createTask(tasks[i]));
  }
  return result;
}

function deleteTasksBatch(params) {
  var ids = params.ids || [];
  var seen = {};
  var unique = [];
  for (var i = 0; i < ids.length; i++) {
    if (!seen[ids[i]]) { seen[ids[i]] = true; unique.push(ids[i]); }
  }
  var deleted = [];
  var errors = [];
  for (var j = 0; j < unique.length; j++) {
    try {
      deleteTask({id: unique[j]});
      deleted.push(unique[j]);
    } catch (e) {
      errors.push({id: unique[j], error: e.message || String(e)});
    }
  }
  var result = {deleted: deleted.length, ids: deleted};
  if (errors.length > 0) { result.errors = errors; }
  return result;
}

function moveTasksBatch(params) {
  var doc = getDocument();
  var project = findProjectByName(doc, params.project);
  if (!project) { throw new Error('Project not found'); }
  var result = [];
  var errors = [];
  var ids = params.ids || [];
  for (var i = 0; i < ids.length; i++) {
    var task = findTaskById(doc, ids[i]);
    if (!task) { errors.push({id: ids[i], error: 'Task not found'}); continue; }
    try {
      project.tasks.push(task);
    } catch (e) {
      try { task.project = project; } catch (e2) {
        errors.push({id: ids[i], error: e.message || String(e)});
        continue;
      }
    }
    result.push(taskToJSON(task));
  }
  var out = {moved: result.length, tasks: result};
  if (errors.length > 0) { out.errors = errors; }
  return out;
}

function listNotifications(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var alarms = arrayify(firstValue(task, ['alarms', 'alerts', 'notifications']));
  return alarms.map(function(alarm) {
    return {
      id: normalizeId(safeCall(alarm, 'id')),
      kind: safeCall(alarm, 'kind') || safeCall(alarm, 'type'),
      fireDate: toISO(firstValue(alarm, ['absoluteFireDate', 'fireDate', 'date'])),
      repeatInterval: safeCall(alarm, 'repeatInterval'),
      isSnoozed: safeCall(alarm, 'isSnoozed'),
      usesFloatingTimeZone: safeCall(alarm, 'usesFloatingTimeZone'),
      relativeFireOffset: safeCall(alarm, 'relativeFireOffset')
    };
  });
}

function addNotification(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var fireDate = parseDate(params.date);
  if (!fireDate) { throw new Error('Invalid date'); }
  var alarm = null;
  try {
    alarm = task.make({new: 'alarm', withProperties: {kind: 'absolute', absoluteFireDate: fireDate}});
  } catch (e) {
    try {
      alarm = task.make({new: 'alarm', withProperties: {absoluteFireDate: fireDate}});
    } catch (e2) {
      throw new Error('Unable to create notification: ' + e2.message);
    }
  }
  return {
    id: normalizeId(safeCall(alarm, 'id')),
    kind: safeCall(alarm, 'kind'),
    fireDate: toISO(firstValue(alarm, ['absoluteFireDate', 'fireDate']))
  };
}

function removeNotification(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var alarms = arrayify(firstValue(task, ['alarms', 'alerts', 'notifications']));
  var targetId = normalizeId(params.notificationId);
  for (var i = 0; i < alarms.length; i++) {
    if (normalizeId(safeCall(alarms[i], 'id')) === targetId) {
      alarms[i].delete();
      return {deleted: true, notificationId: params.notificationId};
    }
  }
  throw new Error('Notification not found');
}

function setTaskRepetition(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  if (params.rule === null || params.rule === undefined || params.rule === '') {
    try { task.repetitionRule = null; } catch (e) {}
    try { task.recurrenceRule = null; } catch (e) {}
    return taskToJSON(task);
  }
  var applied = false;
  try {
    task.repetitionRule = params.rule;
    applied = true;
  } catch (e) {
    try {
      task.recurrenceRule = params.rule;
      applied = true;
    } catch (e2) {
      throw new Error('Unable to set repetition rule: ' + e2.message);
    }
  }
  if (params.scheduleType) {
    var methodMap = {'fixed': 'fixed', 'due': 'due date', 'defer': 'defer date'};
    try { task.repetitionMethod = methodMap[params.scheduleType] || params.scheduleType; } catch (e) {}
  }
  if (params.anchorDateKey !== undefined) {
    safeSet(task, 'anchorDateKey', params.anchorDateKey);
  }
  if (params.catchUpAutomatically !== undefined) {
    safeSet(task, 'catchUpAutomatically', params.catchUpAutomatically);
  }
  return taskToJSON(task);
}

function markReviewed(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) { throw new Error('Project not found'); }
  try {
    if (typeof project.markReviewed === 'function') {
      project.markReviewed();
    } else {
      safeSet(project, 'lastReviewDate', new Date());
    }
  } catch (e) {
    safeSet(project, 'lastReviewDate', new Date());
  }
  return projectToJSON(project);
}

function dropTask(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var dropped = false;
  try {
    if (typeof task.drop === 'function') {
      task.drop(false);
      dropped = true;
    } else {
      dropped = safeSet(task, 'dropped', true);
    }
  } catch (e) {
    dropped = safeSet(task, 'dropped', true);
  }
  if (!dropped) { throw new Error('Unable to drop task — operation not supported in this OmniFocus version'); }
  return taskToJSON(task);
}

function importTaskpaper(params) {
  var doc = getDocument();
  var text = params.text;
  if (!text) { throw new Error('Missing text parameter'); }
  var target = null;
  if (params.project) {
    target = findProjectByName(doc, params.project);
    if (!target) { throw new Error('Project not found'); }
  }
  // JXA: line-by-line fallback — TaskPaper metadata (@tags, @due, indentation) is NOT preserved
  var tasks = [];
  var moveFailures = 0;
  try {
    var lines = text.split('\n');
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i].replace(/^[\s-]*/, '');
      if (!line) { continue; }
      var taskObj = doc.make({new: 'inboxTask', withProperties: {name: line}});
      if (target) {
        var moved = false;
        try { target.tasks.push(taskObj); moved = true; } catch (e) {
          try { taskObj.project = target; moved = true; } catch (e2) {}
        }
        if (!moved) { moveFailures++; }
      }
      tasks.push(taskToJSON(taskObj));
    }
  } catch (e) {
    throw new Error('Unable to import TaskPaper text: ' + e.message);
  }
  var result = {imported: tasks.length, tasks: tasks, warning: 'JXA backend: TaskPaper metadata (tags, dates, hierarchy) was stripped. Only task names were imported. Use OmniAutomation backend for full TaskPaper support.'};
  if (moveFailures > 0) {
    result.warning += ' ' + moveFailures + ' task(s) could not be moved to the target project.';
  }
  return result;
}

function addRelativeNotification(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var offset = -(params.beforeSeconds || 0);
  var alarm = null;
  try {
    alarm = task.make({new: 'alarm', withProperties: {relativeFireOffset: offset}});
  } catch (e) {
    throw new Error('Unable to create relative notification: ' + e.message);
  }
  return {
    id: normalizeId(safeCall(alarm, 'id')),
    kind: safeCall(alarm, 'kind'),
    relativeFireOffset: safeCall(alarm, 'relativeFireOffset')
  };
}

function moveTag(params) {
  var doc = getDocument();
  var tag = findTagById(doc, params.id);
  if (!tag) { throw new Error('Tag not found'); }
  if (params.parentTag) {
    var parent = findTagByName(doc, params.parentTag);
    if (!parent) { throw new Error('Parent tag not found'); }
    try { tag.move({to: parent.tags}); } catch (e) {
      throw new Error('Unable to move tag: ' + e.message);
    }
  } else {
    try { tag.move({to: doc.tags}); } catch (e) {
      throw new Error('Unable to move tag to root: ' + e.message);
    }
  }
  return tagToJSON(tag);
}

function moveFolder(params) {
  var doc = getDocument();
  var folder = findFolderById(doc, params.id);
  if (!folder) { throw new Error('Folder not found'); }
  if (params.parentFolder) {
    var parent = findFolderByName(doc, params.parentFolder);
    if (!parent) { throw new Error('Parent folder not found'); }
    try { folder.move({to: parent.folders}); } catch (e) {
      throw new Error('Unable to move folder: ' + e.message);
    }
  } else {
    try { folder.move({to: doc.folders}); } catch (e) {
      throw new Error('Unable to move folder to root: ' + e.message);
    }
  }
  return folderToJSON(folder);
}

function convertToProject(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  // JXA: manual copy+delete approach
  var name = safeCall(task, 'name');
  var note = safeCall(task, 'note');
  var flagged = safeCall(task, 'flagged');
  var dueDate = toISO(firstValue(task, ['dueDate']));
  var deferDate = toISO(firstValue(task, ['deferDate']));
  var project = doc.make({new: 'project', withProperties: {name: name}});
  if (note) { safeSet(project, 'note', note); }
  if (flagged) { safeSet(project, 'flagged', flagged); }
  var due = parseDate(dueDate);
  if (due) { safeSet(project, 'dueDate', due); }
  var defer = parseDate(deferDate);
  if (defer) { safeSet(project, 'deferDate', defer); }
  // Move children — track failures
  var children = arrayify(firstValue(task, ['tasks', 'children', 'flattenedTasks']));
  var childErrors = [];
  for (var i = 0; i < children.length; i++) {
    try { project.tasks.push(children[i]); } catch (e) { childErrors.push(i); }
  }
  if (childErrors.length > 0 && childErrors.length === children.length && children.length > 0) {
    // All children failed to move — delete the empty project and abort
    try { project.delete(); } catch (e) {}
    throw new Error('Failed to move any child tasks to new project');
  }
  try { task.delete(); } catch (e) {
    // Task deletion failed — project was created but original task remains
  }
  var result = projectToJSON(project);
  if (childErrors.length > 0) {
    result.warning = childErrors.length + ' of ' + children.length + ' child tasks could not be moved';
  }
  return result;
}

function duplicateProject(params) {
  var doc = getDocument();
  var project = findProjectById(doc, params.id);
  if (!project) { throw new Error('Project not found'); }
  var newName = params.name || (safeCall(project, 'name') + ' (copy)');
  var newProject = doc.make({new: 'project', withProperties: {name: newName}});
  safeSet(newProject, 'note', safeCall(project, 'note'));
  safeSet(newProject, 'flagged', safeCall(project, 'flagged'));
  var due = firstValue(project, ['dueDate']);
  if (due) { safeSet(newProject, 'dueDate', due); }
  var defer = firstValue(project, ['deferDate']);
  if (defer) { safeSet(newProject, 'deferDate', defer); }
  return projectToJSON(newProject);
}

function getForecastTag(params) {
  // JXA does not support Tag.forecastTag
  return null;
}

function cleanUp(params) {
  var doc = getDocument();
  try {
    if (typeof doc.compact === 'function') {
      doc.compact();
    }
  } catch (e) {}
  return {success: true};
}

function getSettings(params) {
  // JXA has limited settings access
  return {backend: 'jxa', note: 'Settings access is limited in JXA backend. Use OmniAutomation backend for full settings.'};
}

function listLinkedFiles(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var urls = [];
  try {
    var linked = arrayify(firstValue(task, ['linkedFileURLs', 'attachments']));
    for (var i = 0; i < linked.length; i++) {
      var u = linked[i];
      urls.push(typeof u === 'string' ? u : String(u));
    }
  } catch (e) {}
  return {id: params.id, linkedFileURLs: urls};
}

function addLinkedFile(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  try {
    if (typeof task.addLinkedFileURL === 'function') {
      task.addLinkedFileURL(params.url);
    } else {
      throw new Error('addLinkedFileURL not available in JXA');
    }
  } catch (e) { throw new Error('Unable to add linked file: ' + e.message); }
  return {success: true, url: params.url};
}

function removeLinkedFile(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  try {
    if (typeof task.removeLinkedFileWithURL === 'function') {
      task.removeLinkedFileWithURL(params.url);
    } else {
      throw new Error('removeLinkedFileWithURL not available in JXA');
    }
  } catch (e) { throw new Error('Unable to remove linked file: ' + e.message); }
  return {success: true, url: params.url};
}

function searchProjects(params) {
  var doc = getDocument();
  var q = (params.query || '').toLowerCase();
  var projects = arrayify(safeCall(doc, 'flattenedProjects'));
  var results = [];
  for (var i = 0; i < projects.length; i++) {
    var name = safeCall(projects[i], 'name') || '';
    if (name.toLowerCase().indexOf(q) >= 0) {
      results.push(projectToJSON(projects[i]));
    }
  }
  return results;
}

function searchFolders(params) {
  var doc = getDocument();
  var q = (params.query || '').toLowerCase();
  var folders = [];
  collectFoldersFrom(doc, folders, {});
  var results = [];
  for (var i = 0; i < folders.length; i++) {
    var name = safeCall(folders[i], 'name') || '';
    if (name.toLowerCase().indexOf(q) >= 0) {
      results.push(folderToJSON(folders[i]));
    }
  }
  return results;
}

function searchTasksNative(params) {
  // JXA fallback: same as searchTasks
  return searchTasks(params);
}

function lookupUrl(params) {
  // JXA: limited support
  return {error: 'URL lookup not available in JXA backend. Use OmniAutomation backend.'};
}

function getForecastDays(params) {
  // JXA: fallback to getForecast
  return getForecast(params);
}

function getFocus(params) {
  // JXA: limited support
  return {focused: [], note: 'Focus access limited in JXA backend.'};
}

function setFocus(params) {
  // JXA: limited support
  return {error: 'Focus setting not available in JXA backend. Use OmniAutomation backend.'};
}

function undoAction(params) {
  // JXA: limited support
  return {error: 'Undo not available in JXA backend. Use OmniAutomation backend.'};
}

function redoAction(params) {
  // JXA: limited support
  return {error: 'Redo not available in JXA backend. Use OmniAutomation backend.'};
}

function saveAction(params) {
  var doc = getDocument();
  try {
    if (typeof doc.save === 'function') { doc.save(); }
  } catch (e) {}
  return {success: true};
}

function duplicateTasksBatch(params) {
  var doc = getDocument();
  var ids = params.ids || [];
  var results = [];
  var errors = [];
  for (var i = 0; i < ids.length; i++) {
    var task = findTaskById(doc, ids[i]);
    if (task) {
      try {
        var dup = task.duplicate();
        results.push(taskToJSON(dup));
      } catch (e) {
        errors.push({id: ids[i], error: e.message || String(e)});
      }
    }
  }
  var result = {duplicated: results.length, tasks: results};
  if (errors.length > 0) { result.errors = errors; }
  return result;
}

function duplicateTagsAction(params) {
  var doc = getDocument();
  var ids = params.ids || [];
  var results = [];
  for (var i = 0; i < ids.length; i++) {
    var tag = findTagById(doc, ids[i]);
    if (tag) {
      try {
        var newTag = doc.make({new: 'tag', withProperties: {name: safeCall(tag, 'name') + ' Copy'}});
        results.push(tagToJSON(newTag));
      } catch (e) {
        results.push({error: 'Failed to duplicate tag ' + ids[i] + ': ' + e.message});
      }
    }
  }
  return {duplicated: results.length, tags: results};
}

function moveProjectsBatch(params) {
  var doc = getDocument();
  var ids = params.ids || [];
  if (params.folder) {
    var targetFolder = findFolderByName(doc, params.folder);
    if (!targetFolder) { throw new Error('Folder not found: ' + params.folder); }
  }
  var results = [];
  var errors = [];
  for (var i = 0; i < ids.length; i++) {
    var project = findProjectById(doc, ids[i]);
    if (project) {
      try {
        if (targetFolder) {
          project.move({to: targetFolder.projects});
        }
        results.push(projectToJSON(project));
      } catch (e) {
        errors.push({id: ids[i], error: e.message || String(e)});
      }
    }
  }
  var result = {moved: results.length, projects: results};
  if (errors.length > 0) { result.errors = errors; }
  return result;
}

function reorderTaskTags(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var tagIds = params.tagIds || [];
  // Resolve all tags first before clearing
  var newTags = [];
  var missing = [];
  for (var i = 0; i < tagIds.length; i++) {
    var tag = findTagById(doc, tagIds[i]);
    if (tag) { newTags.push(tag); } else { missing.push(tagIds[i]); }
  }
  if (missing.length > 0) {
    throw new Error('Tags not found: ' + missing.join(', '));
  }
  // Save original tags for rollback
  var origTags = [];
  try { origTags = arrayify(task.tags()); } catch (e) { try { origTags = arrayify(task.tags); } catch (e2) {} }
  try {
    task.tags = newTags;
  } catch (e) {
    // Rollback on failure
    try { task.tags = origTags; } catch (e2) {}
    throw new Error('Failed to reorder tags: ' + e.message);
  }
  return taskToJSON(task);
}

function copyTasksAction(params) {
  // JXA: limited pasteboard support
  return {error: 'Copy tasks to pasteboard not available in JXA backend. Use OmniAutomation backend.'};
}

function pasteTasksAction(params) {
  // JXA: limited pasteboard support
  return {error: 'Paste tasks from pasteboard not available in JXA backend. Use OmniAutomation backend.'};
}

function nextRepetitionDate(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var rule = safeCall(task, 'repetitionRule');
  if (!rule) { return {nextDate: null, note: 'No repetition rule set'}; }
  try {
    var afterDate = params.afterDate ? parseDate(params.afterDate) : new Date();
    if (typeof rule.firstDateAfterDate === 'function') {
      var next = rule.firstDateAfterDate(afterDate);
      return {nextDate: toISO(next)};
    }
  } catch (e) {}
  return {nextDate: null, note: 'Unable to compute next repetition date in JXA'};
}

function setForecastTagAction(params) {
  // JXA: not available
  return {error: 'Setting forecast tag not available in JXA backend. Use OmniAutomation backend.'};
}

function setNotificationRepeat(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) { throw new Error('Task not found'); }
  var alarms = arrayify(firstValue(task, ['alarms', 'alerts', 'notifications']));
  var targetId = normalizeId(params.notificationId);
  for (var i = 0; i < alarms.length; i++) {
    if (normalizeId(safeCall(alarms[i], 'id')) === targetId) {
      safeSet(alarms[i], 'repeatInterval', params.repeatInterval || 0);
      return {success: true, notificationId: params.notificationId, repeatInterval: params.repeatInterval};
    }
  }
  throw new Error('Notification not found');
}

var input = readInput();
var action = input.action;
var params = input.params || {};
var result = null;

switch (action) {
  case 'list_tasks':
    result = listTasks(params);
    break;
  case 'list_inbox':
    result = listInbox();
    break;
  case 'list_projects':
    result = listProjects();
    break;
  case 'list_tags':
    result = listTags();
    break;
  case 'list_perspectives':
    result = listPerspectives();
    break;
  case 'list_folders':
    result = listFolders(params);
    break;
  case 'create_folder':
    result = createFolder(params);
    break;
  case 'move_project':
    result = moveProject(params);
    break;
  case 'list_flagged':
    result = listFlagged(params);
    break;
  case 'list_overdue':
    result = listOverdue(params);
    break;
  case 'list_available':
    result = listAvailable(params);
    break;
  case 'search_tasks':
    result = searchTasks(params);
    break;
  case 'list_task_children':
    result = listTaskChildren(params);
    break;
  case 'get_task_parent':
    result = getTaskParent(params);
    break;
  case 'get_task':
    result = getTask(params);
    break;
  case 'get_project':
    result = getProject(params);
    break;
  case 'get_tag':
    result = getTag(params);
    break;
  case 'create_task':
    result = createTask(params);
    break;
  case 'create_project':
    result = createProject(params);
    break;
  case 'create_tag':
    result = createTag(params);
    break;
  case 'update_task':
    result = updateTask(params);
    break;
  case 'set_project_sequential':
    result = setProjectSequential(params);
    break;
  case 'process_inbox':
    result = processInbox(params);
    break;
  case 'update_project':
    result = updateProject(params);
    break;
  case 'update_tag':
    result = updateTag(params);
    break;
  case 'complete_task':
    result = completeTask(params);
    break;
  case 'complete_project':
    result = completeProject(params);
    break;
  case 'delete_task':
    result = deleteTask(params);
    break;
  case 'delete_project':
    result = deleteProject(params);
    break;
  case 'delete_tag':
    result = deleteTag(params);
    break;
  case 'uncomplete_task':
    result = uncompleteTask(params);
    break;
  case 'uncomplete_project':
    result = uncompleteProject(params);
    break;
  case 'append_to_note':
    result = appendToNote(params);
    break;
  case 'search_tags':
    result = searchTags(params);
    break;
  case 'set_project_status':
    result = setProjectStatus(params);
    break;
  case 'get_folder':
    result = getFolder(params);
    break;
  case 'update_folder':
    result = updateFolder(params);
    break;
  case 'delete_folder':
    result = deleteFolder(params);
    break;
  case 'get_task_counts':
    result = getTaskCounts(params);
    break;
  case 'get_project_counts':
    result = getProjectCounts(params);
    break;
  case 'get_forecast':
    result = getForecast(params);
    break;
  case 'create_subtask':
    result = createSubtask(params);
    break;
  case 'duplicate_task':
    result = duplicateTask(params);
    break;
  case 'create_tasks_batch':
    result = createTasksBatch(params);
    break;
  case 'delete_tasks_batch':
    result = deleteTasksBatch(params);
    break;
  case 'move_tasks_batch':
    result = moveTasksBatch(params);
    break;
  case 'list_notifications':
    result = listNotifications(params);
    break;
  case 'add_notification':
    result = addNotification(params);
    break;
  case 'remove_notification':
    result = removeNotification(params);
    break;
  case 'set_task_repetition':
    result = setTaskRepetition(params);
    break;
  case 'mark_reviewed':
    result = markReviewed(params);
    break;
  case 'drop_task':
    result = dropTask(params);
    break;
  case 'import_taskpaper':
    result = importTaskpaper(params);
    break;
  case 'add_relative_notification':
    result = addRelativeNotification(params);
    break;
  case 'move_tag':
    result = moveTag(params);
    break;
  case 'move_folder':
    result = moveFolder(params);
    break;
  case 'convert_to_project':
    result = convertToProject(params);
    break;
  case 'duplicate_project':
    result = duplicateProject(params);
    break;
  case 'get_forecast_tag':
    result = getForecastTag(params);
    break;
  case 'clean_up':
    result = cleanUp(params);
    break;
  case 'get_settings':
    result = getSettings(params);
    break;
  case 'list_linked_files':
    result = listLinkedFiles(params);
    break;
  case 'add_linked_file':
    result = addLinkedFile(params);
    break;
  case 'remove_linked_file':
    result = removeLinkedFile(params);
    break;
  case 'search_projects':
    result = searchProjects(params);
    break;
  case 'search_folders':
    result = searchFolders(params);
    break;
  case 'search_tasks_native':
    result = searchTasksNative(params);
    break;
  case 'lookup_url':
    result = lookupUrl(params);
    break;
  case 'get_forecast_days':
    result = getForecastDays(params);
    break;
  case 'get_focus':
    result = getFocus(params);
    break;
  case 'set_focus':
    result = setFocus(params);
    break;
  case 'undo':
    result = undoAction(params);
    break;
  case 'redo':
    result = redoAction(params);
    break;
  case 'save':
    result = saveAction(params);
    break;
  case 'duplicate_tasks_batch':
    result = duplicateTasksBatch(params);
    break;
  case 'duplicate_tags':
    result = duplicateTagsAction(params);
    break;
  case 'move_projects_batch':
    result = moveProjectsBatch(params);
    break;
  case 'reorder_task_tags':
    result = reorderTaskTags(params);
    break;
  case 'copy_tasks':
    result = copyTasksAction(params);
    break;
  case 'paste_tasks':
    result = pasteTasksAction(params);
    break;
  case 'next_repetition_date':
    result = nextRepetitionDate(params);
    break;
  case 'set_forecast_tag':
    result = setForecastTagAction(params);
    break;
  case 'set_notification_repeat':
    result = setNotificationRepeat(params);
    break;
  default:
    throw new Error('Unknown action: ' + action);
}

console.log(JSON.stringify(result));
"""#

private let omniAutomationScript = #"""
(function() {
  function toISO(date) {
    if (!date) {
      return null;
    }
    try {
      if (date instanceof Date) {
        return date.toISOString();
      }
    } catch (e) {
    }
    return null;
  }

  function safeCall(obj, prop) {
    try {
      if (!obj) {
        return null;
      }
      if (typeof obj[prop] === 'function') {
        return obj[prop]();
      }
      if (obj[prop] !== undefined) {
        return obj[prop];
      }
    } catch (e) {
    }
    return null;
  }

  function safeSet(obj, prop, value) {
    try {
      if (!obj) {
        return false;
      }
      obj[prop] = value;
      return true;
    } catch (e) {
    }
    return false;
  }

  function callIfFunction(obj, prop, args) {
    try {
      if (obj && typeof obj[prop] === 'function') {
        obj[prop].apply(obj, args || []);
        return true;
      }
    } catch (e) {
    }
    return false;
  }

  function firstValue(obj, names) {
    for (var i = 0; i < names.length; i++) {
      var value = safeCall(obj, names[i]);
      if (value !== null && value !== undefined) {
        return value;
      }
    }
    return null;
  }

  function arrayify(value) {
    if (!value) {
      return [];
    }
    if (Array.isArray(value)) {
      return value;
    }
    if (value.length !== undefined) {
      var result = [];
      for (var i = 0; i < value.length; i++) {
        result.push(value[i]);
      }
      return result;
    }
    return [value];
  }

  function normalizeIdString(id) {
    if (!id) {
      return null;
    }
    var match = String(id).match(/^(.+)\.(\d+)$/);
    if (match && match[1] && match[1].length > 6) {
      return match[1];
    }
    return String(id);
  }

  function normalizeStatus(value) {
    if (!value) {
      return null;
    }
    var status = String(value).toLowerCase();
    if (status.indexOf('active') !== -1) {
      return 'active';
    }
    if (status.indexOf('done') !== -1 || status.indexOf('completed') !== -1) {
      return 'done';
    }
    if (status.indexOf('dropped') !== -1) {
      return 'dropped';
    }
    if (status.indexOf('on hold') !== -1 || status.indexOf('hold') !== -1 || status.indexOf('paused') !== -1) {
      return 'on_hold';
    }
    return String(value);
  }

  function dateValue(value) {
    if (!value) {
      return null;
    }
    if (value instanceof Date) {
      return value;
    }
    var date = new Date(value);
    if (isNaN(date.getTime())) {
      return null;
    }
    return date;
  }

  function isTaskAvailable(task) {
    var available = safeCall(task, 'available');
    if (available !== null && available !== undefined) {
      return !!available;
    }
    var deferDate = dateValue(firstValue(task, ['deferDate']));
    if (!deferDate) {
      return true;
    }
    return deferDate.getTime() <= Date.now();
  }

  function isTaskOverdue(task) {
    var dueDate = dateValue(firstValue(task, ['dueDate']));
    if (!dueDate) {
      return false;
    }
    return dueDate.getTime() < Date.now();
  }

  function getApp() {
    if (typeof app !== 'undefined' && app) {
      return app;
    }
    if (typeof Application !== 'undefined') {
      try {
        return Application('OmniFocus');
      } catch (e) {
      }
    }
    return null;
  }

  function hasDocumentCollections(doc) {
    if (!doc) {
      return false;
    }
    return !!firstValue(doc, [
      'database',
      'flattenedProjects',
      'projects',
      'folders',
      'tasks',
      'flattenedTasks',
      'inbox',
      'inboxTasks',
      'inboxItems',
      'tags',
      'flattenedTags',
      'contexts'
    ]);
  }

  function getDocument() {
    var docCandidate = null;
    if (typeof document !== 'undefined' && document) {
      docCandidate = document;
      if (hasDocumentCollections(docCandidate)) {
        return docCandidate;
      }
    }
    var of = getApp();
    if (!of) {
      throw new Error('OmniFocus application is not available');
    }
    var docValue = firstValue(of, ['defaultDocument']);
    if (docValue) {
      if (typeof docValue === 'function') {
        docValue = docValue();
      }
      if (hasDocumentCollections(docValue)) {
        return docValue;
      }
    }
    var docs = arrayify(firstValue(of, ['documents']));
    if (docs.length > 0) {
      if (hasDocumentCollections(docs[0])) {
        return docs[0];
      }
      return docs[0];
    }
    if (docCandidate) {
      return docCandidate;
    }
    throw new Error('No OmniFocus document found');
  }

  function getDatabase() {
    if (typeof database !== 'undefined' && database) {
      return database;
    }
    var doc = getDocument();
    var dbValue = firstValue(doc, ['database', 'defaultDatabase']);
    if (dbValue) {
      if (typeof dbValue === 'function') {
        dbValue = dbValue();
      }
      if (dbValue) {
        return dbValue;
      }
    }
    var of = getApp();
    if (of) {
      var appDb = firstValue(of, ['defaultDatabase', 'database', 'databases']);
      if (appDb) {
        if (typeof appDb === 'function') {
          appDb = appDb();
        }
        var dbList = arrayify(appDb);
        if (dbList.length > 0) {
          return dbList[0];
        }
        return appDb;
      }
    }
    return doc;
  }

  function normalizeId(value) {
    if (value === null || value === undefined) {
      return null;
    }
    if (typeof value === 'string' || typeof value === 'number') {
      return normalizeIdString(value);
    }
    var primaryKey = safeCall(value, 'primaryKey');
    if (primaryKey !== null && primaryKey !== undefined) {
      return normalizeIdString(primaryKey);
    }
    var uuid = safeCall(value, 'uuid');
    if (uuid !== null && uuid !== undefined) {
      return normalizeIdString(uuid);
    }
    try {
      if (typeof value.toString === 'function') {
        return normalizeIdString(value.toString());
      }
    } catch (e) {
    }
    return null;
  }

  function idValue(obj) {
    var raw = firstValue(obj, ['id', 'identifier', 'uuid']);
    return normalizeId(raw);
  }

  function tagNames(task) {
    var tags = safeCall(task, 'tags');
    if (!tags) {
      tags = safeCall(task, 'contexts');
    }
    return arrayify(tags).map(function(tag) {
      return safeCall(tag, 'name');
    }).filter(function(name) { return name; });
  }

  function projectName(task) {
    var project = firstValue(task, ['containingProject', 'project']);
    if (!project) {
      return null;
    }
    return safeCall(project, 'name');
  }

  function normalizeTaskStatus(ts) {
    if (ts === null || ts === undefined) { return null; }
    var s = String(ts).toLowerCase();
    if (s.indexOf('available') !== -1) { return 'available'; }
    if (s.indexOf('completed') !== -1) { return 'completed'; }
    if (s.indexOf('dropped') !== -1) { return 'dropped'; }
    if (s.indexOf('blocked') !== -1) { return 'blocked'; }
    if (s.indexOf('dueSoon') !== -1 || s.indexOf('duesoon') !== -1) { return 'dueSoon'; }
    if (s.indexOf('next') !== -1) { return 'next'; }
    if (s.indexOf('overdue') !== -1) { return 'overdue'; }
    return s;
  }

  function taskToJSON(task) {
    var ts = firstValue(task, ['taskStatus']);
    var urlVal = null;
    try { var u = safeCall(task, 'url'); if (u) { urlVal = String(u); } } catch (e) {}
    return {
      id: idValue(task),
      name: safeCall(task, 'name'),
      note: safeCall(task, 'note'),
      flagged: safeCall(task, 'flagged'),
      completed: safeCall(task, 'completed'),
      completionDate: toISO(firstValue(task, ['completionDate'])),
      dueDate: toISO(firstValue(task, ['dueDate'])),
      deferDate: toISO(firstValue(task, ['deferDate'])),
      plannedDate: toISO(firstValue(task, ['plannedDate'])),
      effectivePlannedDate: toISO(firstValue(task, ['effectivePlannedDate'])),
      effectiveDueDate: toISO(firstValue(task, ['effectiveDueDate'])),
      effectiveDeferDate: toISO(firstValue(task, ['effectiveDeferDate'])),
      effectiveFlagged: safeCall(task, 'effectiveFlagged'),
      added: toISO(firstValue(task, ['added', 'dateAdded'])),
      modified: toISO(firstValue(task, ['modified', 'dateModified'])),
      taskStatus: normalizeTaskStatus(ts),
      sequential: safeCall(task, 'sequential'),
      completedByChildren: safeCall(task, 'completedByChildren'),
      hasChildren: safeCall(task, 'hasChildren'),
      url: urlVal,
      estimatedMinutes: safeCall(task, 'estimatedMinutes'),
      dropDate: toISO(firstValue(task, ['dropDate'])),
      effectiveCompletedDate: toISO(firstValue(task, ['effectiveCompletedDate'])),
      effectiveDropDate: toISO(firstValue(task, ['effectiveDropDate'])),
      shouldUseFloatingTimeZone: safeCall(task, 'shouldUseFloatingTimeZone'),
      assignedContainer: (function() {
        try {
          var ac = firstValue(task, ['assignedContainer']);
          if (!ac) return null;
          return {id: idValue(ac), name: safeCall(ac, 'name')};
        } catch (e) { return null; }
      })(),
      tags: tagNames(task),
      project: projectName(task),
      inbox: safeCall(task, 'inInbox')
    };
  }

  function appendNote(task, appendText) {
    if (!appendText) {
      return;
    }
    var existing = safeCall(task, 'note') || '';
    var separator = existing ? '\n' : '';
    safeSet(task, 'note', existing + separator + appendText);
  }

  function projectToJSON(project) {
    var status = firstValue(project, ['status', 'projectStatus']);
    var rawStatus = status ? String(status) : null;
    var ri = null;
    try {
      var riObj = safeCall(project, 'reviewInterval');
      if (riObj) {
        ri = {steps: safeCall(riObj, 'steps'), unit: String(safeCall(riObj, 'unit') || '')};
      }
    } catch (e) {}
    var pf = firstValue(project, ['parentFolder', 'folder']);
    var pfName = pf ? safeCall(pf, 'name') : null;
    var pfId = pf ? idValue(pf) : null;
    var ntasks = null;
    var navail = null;
    try {
      var ft = arrayify(firstValue(project, ['flattenedTasks', 'tasks']));
      ntasks = ft.length;
      var ac = 0;
      for (var ti = 0; ti < ft.length; ti++) {
        if (!safeCall(ft[ti], 'completed') && !safeCall(ft[ti], 'dropped')) { ac++; }
      }
      navail = ac;
    } catch (e) {}
    var urlVal = null;
    try { var u = safeCall(project, 'url'); if (u) { urlVal = String(u); } } catch (e) {}
    return {
      id: idValue(project),
      name: safeCall(project, 'name'),
      note: safeCall(project, 'note'),
      status: normalizeStatus(rawStatus),
      statusRaw: rawStatus,
      completed: safeCall(project, 'completed'),
      completionDate: toISO(firstValue(project, ['completionDate'])),
      dueDate: toISO(firstValue(project, ['dueDate'])),
      deferDate: toISO(firstValue(project, ['deferDate'])),
      flagged: safeCall(project, 'flagged'),
      sequential: safeCall(project, 'sequential'),
      containsSingletonActions: safeCall(project, 'containsSingletonActions'),
      estimatedMinutes: safeCall(project, 'estimatedMinutes'),
      lastReviewDate: toISO(firstValue(project, ['lastReviewDate'])),
      nextReviewDate: toISO(firstValue(project, ['nextReviewDate'])),
      reviewInterval: ri,
      parentFolder: pfName,
      parentFolderId: pfId,
      added: toISO(firstValue(project, ['added', 'dateAdded'])),
      modified: toISO(firstValue(project, ['modified', 'dateModified'])),
      numberOfTasks: ntasks,
      numberOfAvailableTasks: navail,
      effectiveDueDate: toISO(firstValue(project, ['effectiveDueDate'])),
      effectiveDeferDate: toISO(firstValue(project, ['effectiveDeferDate'])),
      effectiveFlagged: safeCall(project, 'effectiveFlagged'),
      url: urlVal,
      nextTask: (function() {
        try {
          var nt = firstValue(project, ['nextTask']);
          if (!nt) return null;
          return {id: idValue(nt), name: safeCall(nt, 'name')};
        } catch (e) { return null; }
      })(),
      defaultSingletonActionHolder: safeCall(project, 'defaultSingletonActionHolder'),
      shouldUseFloatingTimeZone: safeCall(project, 'shouldUseFloatingTimeZone'),
      dropDate: toISO(firstValue(project, ['dropDate'])),
      effectiveCompletedDate: toISO(firstValue(project, ['effectiveCompletedDate'])),
      effectiveDropDate: toISO(firstValue(project, ['effectiveDropDate']))
    };
  }

  function tagToJSON(tag) {
    var parentTag = safeCall(tag, 'parent');
    var parentName = null;
    var parentId = null;
    if (parentTag && safeCall(parentTag, 'name')) {
      parentName = safeCall(parentTag, 'name');
      parentId = idValue(parentTag);
    }
    var ts = firstValue(tag, ['status']);
    return {
      id: idValue(tag),
      name: safeCall(tag, 'name'),
      parent: parentName,
      parentId: parentId,
      active: safeCall(tag, 'active'),
      status: ts !== null && ts !== undefined ? String(ts) : null,
      allowsNextAction: safeCall(tag, 'allowsNextAction'),
      childrenAreMutuallyExclusive: safeCall(tag, 'childrenAreMutuallyExclusive'),
      availableTaskCount: (function() { try { return arrayify(safeCall(tag, 'availableTasks')).length; } catch (e) { return null; } })()
    };
  }

  function perspectiveToJSON(perspective) {
    var afr = null;
    try { afr = safeCall(perspective, 'archivedFilterRules'); } catch (e) {}
    var ic = null;
    try { ic = safeCall(perspective, 'iconColor'); } catch (e) {}
    return {
      id: idValue(perspective),
      name: safeCall(perspective, 'name'),
      archivedFilterRules: afr,
      iconColor: ic
    };
  }

  function folderToJSON(folder) {
    var fp = firstValue(folder, ['parent', 'parentFolder']);
    var fpName = null;
    var fpId = null;
    if (fp && safeCall(fp, 'name')) {
      fpName = safeCall(fp, 'name');
      fpId = idValue(fp);
    }
    var ts = firstValue(folder, ['status']);
    return {
      id: idValue(folder),
      name: safeCall(folder, 'name'),
      note: safeCall(folder, 'note'),
      status: ts !== null && ts !== undefined ? String(ts) : null,
      parentId: fpId,
      parentName: fpName,
      projectCount: arrayify(safeCall(folder, 'projects')).length,
      folderCount: arrayify(firstValue(folder, ['folders', 'childFolders'])).length
    };
  }

  function collectFoldersFrom(container, result, seen) {
    var folders = arrayify(firstValue(container, ['folders', 'childFolders']));
    for (var i = 0; i < folders.length; i++) {
      var folder = folders[i];
      var key = idValue(folder) || safeCall(folder, 'name') || String(result.length);
      if (!seen[key]) {
        seen[key] = true;
        result.push(folder);
        collectFoldersFrom(folder, result, seen);
      }
    }
  }

  function collectFromLibrary(targetCtor, result, seen) {
    try {
      if (typeof library === 'undefined') { return; }
      function recurse(container) {
        for (var i = 0; i < container.length; i++) {
          var item = container[i];
          if (!item) { continue; }
          var ctor = item.constructor ? item.constructor.name : '';
          if (ctor === targetCtor) {
            var key = idValue(item) || safeCall(item, 'name') || String(result.length);
            if (!seen[key]) { seen[key] = true; result.push(item); }
          }
          try { recurse(item); } catch (e) {}
        }
      }
      recurse(library);
    } catch (e) {}
  }

  function allFolders(doc) {
    // In OmniAutomation, flattenedFolders is a global (not a doc property).
    // Trying doc.folders returns only top-level, causing an early-return bug
    // where subfolders are never found. Check the global first.
    try {
      if (typeof flattenedFolders !== 'undefined') {
        var gf = arrayify(flattenedFolders);
        if (gf.length > 0) { return gf; }
      }
    } catch(e) {}
    // JXA: doc.flattenedFolders() returns the full flattened list
    var flattened = safeCall(doc, 'flattenedFolders');
    if (flattened) {
      var list = arrayify(flattened);
      if (list.length > 0) { return list; }
    }
    // Recursive fallback for any backend
    var result = [];
    var seen = {};
    collectFoldersFrom(doc, result, seen);
    collectFromLibrary('Folder', result, seen);
    return result;
  }

  function findFolderByName(doc, name) {
    var folders = allFolders(doc);
    for (var i = 0; i < folders.length; i++) {
      if (safeCall(folders[i], 'name') === name) {
        return folders[i];
      }
    }
    return null;
  }

  function findFolderById(doc, id) {
    try { if (typeof Folder !== 'undefined' && typeof Folder.byIdentifier === 'function') { var f = Folder.byIdentifier(id); if (f) { return f; } } } catch (e) {}
    var folders = allFolders(doc);
    for (var i = 0; i < folders.length; i++) {
      if (idValue(folders[i]) === id) {
        return folders[i];
      }
    }
    return null;
  }

  function findProjectByName(doc, name) {
    var projects = allProjects(doc);
    for (var i = 0; i < projects.length; i++) {
      if (safeCall(projects[i], 'name') === name) {
        return projects[i];
      }
    }
    return null;
  }

  function findProjectById(doc, id) {
    try { if (typeof Project !== 'undefined' && typeof Project.byIdentifier === 'function') { var p = Project.byIdentifier(id); if (p) { return p; } } } catch (e) {}
    var projects = allProjects(doc);
    for (var i = 0; i < projects.length; i++) {
      if (idValue(projects[i]) === id) {
        return projects[i];
      }
    }
    return null;
  }

  function collectProjectsFrom(container, result, seen) {
    var projects = arrayify(firstValue(container, ['projects']));
    for (var i = 0; i < projects.length; i++) {
      var project = projects[i];
      var key = idValue(project) || safeCall(project, 'name') || String(result.length);
      if (!seen[key]) {
        seen[key] = true;
        result.push(project);
      }
    }
    var folders = arrayify(firstValue(container, ['folders', 'childFolders']));
    for (var j = 0; j < folders.length; j++) {
      collectProjectsFrom(folders[j], result, seen);
    }
  }

  function allProjects(doc) {
    // In OmniAutomation, flattenedProjects is a global. document.flattenedProjects
    // is null and document.folders is null, so collectProjectsFrom only finds
    // root-level projects. Check the global first.
    try {
      if (typeof flattenedProjects !== 'undefined') {
        var gp = arrayify(flattenedProjects);
        if (gp.length > 0) { return gp; }
      }
    } catch(e) {}
    // JXA: doc.flattenedProjects() returns the full list
    var flattened = safeCall(doc, 'flattenedProjects');
    if (flattened) {
      var list = arrayify(flattened);
      if (list.length > 0) { return list; }
    }
    // Recursive fallback for any backend
    var result = [];
    var seen = {};
    collectProjectsFrom(doc, result, seen);
    collectFromLibrary('Project', result, seen);
    return result;
  }

  function allTags(doc) {
    // Omni Automation: flattenedTags is a global, not a document property.
    // Check it FIRST because doc.tags only returns top-level tags.
    try { if (typeof flattenedTags !== 'undefined' && flattenedTags) {
      var gt = arrayify(flattenedTags);
      if (gt.length > 0) { return gt; }
    } } catch (e) {}
    var tags = arrayify(firstValue(doc, ['flattenedTags', 'tags', 'contexts']));
    if (tags.length > 0) { return tags; }
    return [];
  }

  function findTagByName(doc, name) {
    // Support "Parent > Child" syntax for disambiguation
    var parts = name.split(' > ');
    if (parts.length === 2) {
      var parentName = parts[0].trim();
      var childName = parts[1].trim();
      if (!parentName || !childName) { return null; }
      var tags = allTags(doc);
      for (var i = 0; i < tags.length; i++) {
        if (safeCall(tags[i], 'name') === childName) {
          var parent = safeCall(tags[i], 'parent');
          if (parent && safeCall(parent, 'name') === parentName) {
            return tags[i];
          }
        }
      }
      return null;
    }
    var tags = allTags(doc);
    for (var i = 0; i < tags.length; i++) {
      if (safeCall(tags[i], 'name') === name) {
        return tags[i];
      }
    }
    return null;
  }

  function findTagById(doc, id) {
    try { if (typeof Tag !== 'undefined' && typeof Tag.byIdentifier === 'function') { var tg = Tag.byIdentifier(id); if (tg) { return tg; } } } catch (e) {}
    var tags = allTags(doc);
    for (var i = 0; i < tags.length; i++) {
      if (idValue(tags[i]) === id) {
        return tags[i];
      }
    }
    return null;
  }

  function makeTag(doc, name, active) {
    var tag = null;
    if (typeof Tag !== 'undefined') {
      try {
        tag = new Tag(name);
      } catch (e) {
      }
    }
    if (!tag && doc && typeof doc.make === 'function') {
      var props = {name: name};
      if (active !== undefined) {
        props.active = active;
      }
      try {
        tag = doc.make({new: 'tag', withProperties: props});
      } catch (e) {
      }
    }
    if (!tag && doc && typeof doc.newTag === 'function') {
      try {
        tag = doc.newTag(name);
      } catch (e) {
      }
    }
    if (tag && active !== undefined) {
      safeSet(tag, 'active', active);
    }
    return tag;
  }

  function ensureTag(doc, name, createMissing) {
    var tag = findTagByName(doc, name);
    if (!tag && createMissing) {
      // Support "Parent > Child" syntax for creating nested tags
      var parts = name.split(' > ');
      if (parts.length === 2) {
        var parentName = parts[0].trim();
        var childName = parts[1].trim();
        if (!parentName || !childName) { return makeTag(doc, name); }
        var parentTag = findTagByName(doc, parentName);
        if (!parentTag) {
          parentTag = makeTag(doc, parentName);
        }
        if (parentTag && typeof Tag !== 'undefined') {
          try {
            tag = new Tag(childName, parentTag);
            // Verify the tag was actually placed under parent
            var p = safeCall(tag, 'parent');
            if (!p || safeCall(p, 'name') !== parentName) {
              // Constructor ignored parent arg; move it manually
              try { moveTags([tag], parentTag.ending); } catch (e2) {}
            }
          } catch (e) {}
        }
        // Do NOT fall back to creating a root-level tag — that creates duplicates
      } else {
        tag = makeTag(doc, name);
      }
    }
    return tag;
  }

  function resolveTags(doc, names, createMissing) {
    var result = [];
    arrayify(names).forEach(function(name) {
      if (!name) {
        return;
      }
      var tag = ensureTag(doc, name, createMissing);
      if (tag) {
        result.push(tag);
      }
    });
    return result;
  }

  function findTaskById(doc, id) {
    try { if (typeof Task !== 'undefined' && typeof Task.byIdentifier === 'function') { var t = Task.byIdentifier(id); if (t) { return t; } } } catch (e) {}
    var tasks = allTasks(doc);
    for (var i = 0; i < tasks.length; i++) {
      if (idValue(tasks[i]) === id) {
        return tasks[i];
      }
    }
    return null;
  }

  function addTaskToResult(task, result, seen) {
    var key = idValue(task) || safeCall(task, 'name') || String(result.length);
    if (!seen[key]) {
      seen[key] = true;
      result.push(task);
    }
  }

  function collectTasksFrom(container, result, seen) {
    var tasks = arrayify(firstValue(container, ['tasks']));
    for (var i = 0; i < tasks.length; i++) {
      addTaskToResult(tasks[i], result, seen);
    }
    var projects = arrayify(firstValue(container, ['projects']));
    for (var j = 0; j < projects.length; j++) {
      collectTasksFrom(projects[j], result, seen);
    }
    var folders = arrayify(firstValue(container, ['folders', 'childFolders']));
    for (var k = 0; k < folders.length; k++) {
      collectTasksFrom(folders[k], result, seen);
    }
  }

  function allTasks(doc) {
    // In OmniAutomation, flattenedTasks is a global. document.flattenedTasks
    // is null, so checking the global first ensures all tasks are found.
    try {
      if (typeof flattenedTasks !== 'undefined') {
        var gt = arrayify(flattenedTasks);
        if (gt.length > 0) { return gt; }
      }
    } catch(e) {}
    // JXA: doc.flattenedTasks() returns the full list
    var flattened = safeCall(doc, 'flattenedTasks');
    if (flattened) {
      var list = arrayify(flattened);
      if (list.length > 0) { return list; }
    }
    var result = [];
    var seen = {};
    var inbox = arrayify(firstValue(doc, ['inboxTasks', 'inbox', 'inboxItems']));
    for (var i = 0; i < inbox.length; i++) {
      addTaskToResult(inbox[i], result, seen);
    }
    collectTasksFrom(doc, result, seen);
    collectFromLibrary('Task', result, seen);
    return result;
  }

  function parseDate(value) {
    if (!value) {
      return null;
    }
    // Date-only strings (YYYY-MM-DD) are parsed as UTC midnight by the JS spec,
    // which shifts the displayed date by one day in negative-offset timezones.
    // Construct with integer args instead so the result is local midnight,
    // giving the correct calendar date regardless of where the user is.
    var dateOnly = /^(\d{4})-(\d{2})-(\d{2})$/.exec(value);
    if (dateOnly) {
      var d = new Date(parseInt(dateOnly[1]), parseInt(dateOnly[2]) - 1, parseInt(dateOnly[3]));
      return isNaN(d.getTime()) ? null : d;
    }
    var date = new Date(value);
    if (isNaN(date.getTime())) {
      return null;
    }
    return date;
  }

  function applyTags(task, tags) {
    if (!task) {
      return;
    }
    if (safeSet(task, 'tags', tags)) {
      return;
    }
    if (task && typeof task.addTag === 'function') {
      arrayify(tags).forEach(function(tag) {
        try {
          task.addTag(tag);
        } catch (e) {
        }
      });
    }
  }

  function applyCommonTaskFields(task, params, doc) {
    if (params.name !== undefined) {
      safeSet(task, 'name', params.name);
    }
    if (params.note !== undefined) {
      safeSet(task, 'note', params.note);
    }
    if (params.flagged !== undefined) {
      safeSet(task, 'flagged', params.flagged);
    }
    if (params.estimatedMinutes !== undefined) {
      safeSet(task, 'estimatedMinutes', params.estimatedMinutes);
    }
    var due = parseDate(params.due);
    if (due) {
      safeSet(task, 'dueDate', due);
    }
    if (params.due === null) {
      safeSet(task, 'dueDate', null);
    }
    var deferDate = parseDate(params.defer);
    if (deferDate) {
      safeSet(task, 'deferDate', deferDate);
    }
    if (params.defer === null) {
      safeSet(task, 'deferDate', null);
    }
    if (params.planned !== undefined) {
      var pd = parseDate(params.planned);
      if (pd) { safeSet(task, 'plannedDate', pd); }
      if (params.planned === null) { safeSet(task, 'plannedDate', null); }
    }
    if (params.sequential !== undefined) {
      safeSet(task, 'sequential', params.sequential);
    }
    if (params.completedByChildren !== undefined) {
      safeSet(task, 'completedByChildren', params.completedByChildren);
    }
    if (params.shouldUseFloatingTimeZone !== undefined) {
      safeSet(task, 'shouldUseFloatingTimeZone', params.shouldUseFloatingTimeZone);
    }
    if (params.tags !== undefined) {
      var tagObjects = resolveTags(doc, params.tags, params.createMissingTags === true);
      applyTags(task, tagObjects);
    }
  }

  function assignTaskToProject(task, project) {
    if (project) {
      if (safeSet(task, 'project', project)) {
        return true;
      }
      if (safeSet(task, 'containingProject', project)) {
        return true;
      }
      try {
        if (project.tasks && typeof project.tasks.push === 'function') {
          project.tasks.push(task);
          return true;
        }
      } catch (e) {
      }
      if (callIfFunction(project, 'addTask', [task])) {
        return true;
      }
      return false;
    }
    if (safeSet(task, 'inInbox', true)) {
      return true;
    }
    if (safeSet(task, 'project', null)) {
      return true;
    }
    if (safeSet(task, 'containingProject', null)) {
      return true;
    }
    return false;
  }

  function markTaskComplete(task, completionDate) {
    var date = parseDate(completionDate);
    var marked = false;
    if (callIfFunction(task, 'markComplete')) {
      marked = true;
    }
    if (!marked) {
      marked = safeSet(task, 'completed', true);
    }
    if (date) {
      safeSet(task, 'completionDate', date);
    }
  }

  function listTasks(params) {
    var doc = getDatabase();
    var tasks = allTasks(doc);
    var status = params.status || 'all';
    var projectFilter = params.project || null;
    var tagFilter = params.tag || null;
    var search = params.search ? params.search.toLowerCase() : null;
    var flaggedFilter = params.flagged;
    var limit = params.limit || null;

    var result = [];
    for (var i = 0; i < tasks.length; i++) {
      var task = tasks[i];
      var completed = !!safeCall(task, 'completed');
      if (status === 'completed' && !completed) {
        continue;
      }
      if (status === 'available' && completed) {
        continue;
      }
      if (status === 'available' && !isTaskAvailable(task)) {
        continue;
      }
      if (projectFilter) {
        var projectNameValue = projectName(task);
        if (projectNameValue !== projectFilter) {
          continue;
        }
      }
      if (tagFilter) {
        var tags = tagNames(task);
        if (tags.indexOf(tagFilter) === -1) {
          continue;
        }
      }
      if (search) {
        var name = safeCall(task, 'name') || '';
        var note = safeCall(task, 'note') || '';
        var haystack = (name + ' ' + note).toLowerCase();
        if (haystack.indexOf(search) === -1) {
          continue;
        }
      }
      if (flaggedFilter !== undefined) {
        var flagged = !!safeCall(task, 'flagged');
        if (flagged !== !!flaggedFilter) {
          continue;
        }
      }
      result.push(taskToJSON(task));
      if (limit && result.length >= limit) {
        break;
      }
    }
    return result;
  }

  function listInbox() {
    var doc = getDatabase();
    var inbox = firstValue(doc, ['inboxTasks', 'inbox', 'inboxItems']);
    var tasks = arrayify(inbox);
    return tasks.map(taskToJSON);
  }

  function listProjects() {
    var doc = getDatabase();
    var projects = allProjects(doc);
    return projects.map(projectToJSON);
  }

  function listTags() {
    var doc = getDatabase();
    var tags = allTags(doc);
    return tags.map(tagToJSON);
  }

  function listPerspectives() {
    var of = getApp();
    var perspectives = null;
    if (of) {
      perspectives = firstValue(of, ['perspectives', 'flattenedPerspectives']);
    }
    if (!perspectives) {
      var doc = getDatabase();
      perspectives = firstValue(doc, ['perspectives', 'flattenedPerspectives']);
    }
    return arrayify(perspectives).map(perspectiveToJSON);
  }

  function listFolders() {
    var doc = getDatabase();
    var folders = allFolders(doc);
    return folders.map(folderToJSON);
  }

  function createFolder(params) {
    var doc = getDatabase();
    var parent = null;
    if (params.parentId) {
      parent = findFolderById(doc, params.parentId);
    } else if (params.parent) {
      parent = findFolderByName(doc, params.parent);
    }
    if (params.parent && !parent) {
      throw new Error('Parent folder not found');
    }
    var properties = {name: params.name};
    if (params.note !== undefined) {
      properties.note = params.note;
    }
    var folder = null;
    if (parent && typeof parent.make === 'function') {
      try {
        folder = parent.make({new: 'folder', withProperties: properties});
      } catch (e) {
      }
    }
    if (!folder && doc && typeof doc.make === 'function') {
      try {
        folder = doc.make({new: 'folder', withProperties: properties});
      } catch (e2) {
      }
    }
    if (parent && folder) {
      safeSet(folder, 'containingFolder', parent);
    }
    if (!folder) {
      throw new Error('Unable to create folder');
    }
    return folderToJSON(folder);
  }

  function moveProject(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.projectId);
    if (!project) {
      throw new Error('Project not found');
    }
    var target = null;
    if (params.folderId) {
      target = findFolderById(doc, params.folderId);
    } else if (params.folder) {
      target = findFolderByName(doc, params.folder);
    }
    if ((params.folderId || params.folder) && !target) {
      if (params.createMissingFolder === true && params.folder) {
        var created = createFolder({name: params.folder});
        if (created && created.id) {
          target = findFolderById(doc, created.id);
        }
        if (!target) {
          target = findFolderByName(doc, params.folder);
        }
      } else {
        throw new Error('Folder not found');
      }
    }
    if (target) {
      moveSections([project], target.ending);
    } else {
      moveSections([project], document.ending);
    }
    return projectToJSON(project);
  }

  function listFlagged(params) {
    var query = params || {};
    query.flagged = true;
    return listTasks(query);
  }

  function listOverdue(params) {
    var doc = getDatabase();
    var tasks = allTasks(doc);
    var includeCompleted = params.includeCompleted === true;
    var limit = params.limit || null;
    var result = [];
    for (var i = 0; i < tasks.length; i++) {
      var task = tasks[i];
      if (!includeCompleted && !!safeCall(task, 'completed')) {
        continue;
      }
      if (!isTaskOverdue(task)) {
        continue;
      }
      result.push(taskToJSON(task));
      if (limit && result.length >= limit) {
        break;
      }
    }
    return result;
  }

  function listAvailable(params) {
    var doc = getDatabase();
    var tasks = allTasks(doc);
    var includeCompleted = params.includeCompleted === true;
    var limit = params.limit || null;
    var result = [];
    for (var i = 0; i < tasks.length; i++) {
      var task = tasks[i];
      if (!includeCompleted && !!safeCall(task, 'completed')) {
        continue;
      }
      if (!isTaskAvailable(task)) {
        continue;
      }
      result.push(taskToJSON(task));
      if (limit && result.length >= limit) {
        break;
      }
    }
    return result;
  }

  function searchTasks(params) {
    return listTasks(params);
  }

  function listTaskChildren(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) {
      throw new Error('Task not found');
    }
    var children = firstValue(task, ['tasks', 'subtasks', 'childTasks']);
    return arrayify(children).map(taskToJSON);
  }

  function getTaskParent(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) {
      throw new Error('Task not found');
    }
    var parent = firstValue(task, ['containingTask', 'parentTask']);
    if (!parent) {
      return null;
    }
    return taskToJSON(parent);
  }

  function getTask(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) {
      throw new Error('Task not found');
    }
    return taskToJSON(task);
  }

  function getProject(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) {
      throw new Error('Project not found');
    }
    return projectToJSON(project);
  }

  function getTag(params) {
    var doc = getDatabase();
    var tag = findTagById(doc, params.id);
    if (!tag) {
      throw new Error('Tag not found');
    }
    return tagToJSON(tag);
  }

  function makeProject(doc, params) {
    var project = null;
    if (typeof Project !== 'undefined') {
      try {
        project = new Project(params.name);
      } catch (e) {
      }
    }
    if (!project && doc && typeof doc.make === 'function') {
      var properties = {name: params.name};
      if (params.note !== undefined) {
        properties.note = params.note;
      }
      if (params.flagged !== undefined) {
        properties.flagged = params.flagged;
      }
      var due = parseDate(params.due);
      if (due) {
        properties.dueDate = due;
      }
      var deferDate = parseDate(params.defer);
      if (deferDate) {
        properties.deferDate = deferDate;
      }
      try {
        project = doc.make({new: 'project', withProperties: properties});
      } catch (e) {
      }
    }
    if (!project && doc && typeof doc.newProject === 'function') {
      try {
        project = doc.newProject(params.name);
      } catch (e) {
      }
    }
    if (!project) {
      throw new Error('Unable to create project');
    }
    applyCommonProjectFields(project, params);
    return project;
  }

  function makeTask(doc, params, project) {
    var task = null;
    if (typeof Task !== 'undefined') {
      try {
        task = new Task(params.name, project || null);
      } catch (e) {
      }
      if (!task) {
        try {
          task = new Task(params.name);
        } catch (e2) {
        }
      }
    }
    if (!task && project && typeof project.make === 'function') {
      try {
        task = project.make({new: 'task', withProperties: {name: params.name}});
      } catch (e) {
      }
    }
    if (!task && doc && typeof doc.make === 'function') {
      var typeName = project ? 'task' : 'inbox task';
      try {
        task = doc.make({new: typeName, withProperties: {name: params.name}});
      } catch (e) {
      }
    }
    if (!task && doc && typeof doc.newTask === 'function') {
      try {
        task = doc.newTask(params.name, project || null);
      } catch (e) {
      }
    }
    if (!task) {
      throw new Error('Unable to create task');
    }
    return task;
  }

  function createTask(params) {
    var doc = getDatabase();
    var projectNameValue = params.project || null;
    var createMissingProject = params.createMissingProject === true;
    var project = null;
    if (projectNameValue && !params.inbox) {
      project = findProjectByName(doc, projectNameValue);
      if (!project && createMissingProject) {
        project = makeProject(doc, {name: projectNameValue});
      }
      if (!project) {
        throw new Error('Project not found');
      }
    }
    var task = makeTask(doc, params, project);
    applyCommonTaskFields(task, params, doc);
    if (project) {
      assignTaskToProject(task, project);
    }
    return taskToJSON(task);
  }

  function createProject(params) {
    var doc = getDatabase();
    var project = makeProject(doc, params);
    return projectToJSON(project);
  }

  function createTag(params) {
    var doc = getDatabase();
    var tag = makeTag(doc, params.name, params.active);
    if (!tag) {
      throw new Error('Unable to create tag');
    }
    return tagToJSON(tag);
  }

  function updateTask(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) {
      throw new Error('Task not found');
    }
    applyCommonTaskFields(task, params, doc);
    if (params.project !== undefined) {
      if (params.project) {
        var project = findProjectByName(doc, params.project);
        if (!project && params.createMissingProject === true) {
          project = makeProject(doc, {name: params.project});
        }
        if (!project) {
          throw new Error('Project not found');
        }
        assignTaskToProject(task, project);
      } else {
        assignTaskToProject(task, null);
      }
    }
    return taskToJSON(task);
  }

  function setProjectSequential(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) {
      throw new Error('Project not found');
    }
    var sequential = params.sequential === true;
    var applied = false;
    if (safeSet(project, 'sequential', sequential)) {
      applied = true;
    } else if (safeSet(project, 'parallel', !sequential)) {
      applied = true;
    }
    if (!applied) {
      throw new Error('Unable to update project sequencing');
    }
    return projectToJSON(project);
  }

  function processInbox(params) {
    var doc = getDatabase();
    var inbox = arrayify(firstValue(doc, ['inboxTasks', 'inbox', 'inboxItems']));
    var limit = params.limit || null;
    var project = null;
    if (params.projectId) {
      project = findProjectById(doc, params.projectId);
    } else if (params.project) {
      project = findProjectByName(doc, params.project);
      if (!project && params.createMissingProject === true) {
        project = makeProject(doc, {name: params.project});
      }
    }
    if ((params.projectId || params.project) && !project) {
      throw new Error('Project not found');
    }
    var tagObjects = null;
    if (params.tags !== undefined) {
      tagObjects = resolveTags(doc, params.tags, params.createMissingTags === true);
    }
    var result = [];
    for (var i = 0; i < inbox.length; i++) {
      var task = inbox[i];
      if (params.flagged !== undefined) {
        safeSet(task, 'flagged', params.flagged);
      }
      if (params.estimatedMinutes !== undefined) {
        safeSet(task, 'estimatedMinutes', params.estimatedMinutes);
      }
      var due = parseDate(params.due);
      if (due) {
        safeSet(task, 'dueDate', due);
      }
      if (params.due === null) {
        safeSet(task, 'dueDate', null);
      }
      var deferDate = parseDate(params.defer);
      if (deferDate) {
        safeSet(task, 'deferDate', deferDate);
      }
      if (params.defer === null) {
        safeSet(task, 'deferDate', null);
      }
      if (tagObjects) {
        applyTags(task, tagObjects);
      }
      if (params.noteAppend) {
        appendNote(task, params.noteAppend);
      }
      if (project && params.keepInInbox !== true) {
        assignTaskToProject(task, project);
      }
      result.push(taskToJSON(task));
      if (limit && result.length >= limit) {
        break;
      }
    }
    return result;
  }

  function applyCommonProjectFields(project, params) {
    if (params.name !== undefined) {
      safeSet(project, 'name', params.name);
    }
    if (params.note !== undefined) {
      safeSet(project, 'note', params.note);
    }
    if (params.flagged !== undefined) {
      safeSet(project, 'flagged', params.flagged);
    }
    var due = parseDate(params.due);
    if (due) {
      safeSet(project, 'dueDate', due);
    }
    if (params.due === null) {
      safeSet(project, 'dueDate', null);
    }
    var deferDate = parseDate(params.defer);
    if (deferDate) {
      safeSet(project, 'deferDate', deferDate);
    }
    if (params.defer === null) {
      safeSet(project, 'deferDate', null);
    }
    if (params.estimatedMinutes !== undefined) {
      safeSet(project, 'estimatedMinutes', params.estimatedMinutes);
    }
    if (params.sequential !== undefined) {
      safeSet(project, 'sequential', params.sequential);
    }
    if (params.containsSingletonActions !== undefined) {
      safeSet(project, 'containsSingletonActions', params.containsSingletonActions);
    }
    if (params.reviewInterval !== undefined && params.reviewInterval) {
      try {
        var ri = safeCall(project, 'reviewInterval');
        if (ri) {
          safeSet(ri, 'steps', params.reviewInterval.steps || 1);
          safeSet(ri, 'unit', params.reviewInterval.unit || 'weeks');
        }
      } catch (e) {}
    }
    if (params.shouldUseFloatingTimeZone !== undefined) {
      safeSet(project, 'shouldUseFloatingTimeZone', params.shouldUseFloatingTimeZone);
    }
  }

  function updateProject(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) {
      throw new Error('Project not found');
    }
    applyCommonProjectFields(project, params);
    return projectToJSON(project);
  }

  function updateTag(params) {
    var doc = getDatabase();
    var tag = findTagById(doc, params.id);
    if (!tag) {
      throw new Error('Tag not found');
    }
    if (params.name !== undefined) {
      safeSet(tag, 'name', params.name);
    }
    if (params.active !== undefined) {
      safeSet(tag, 'active', params.active);
    }
    if (params.allowsNextAction !== undefined) {
      safeSet(tag, 'allowsNextAction', params.allowsNextAction);
    }
    return tagToJSON(tag);
  }

  function completeTask(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) {
      throw new Error('Task not found');
    }
    markTaskComplete(task, params.completionDate || null);
    return taskToJSON(task);
  }

  function markProjectComplete(project, completionDate) {
    var date = parseDate(completionDate);
    var marked = false;
    if (callIfFunction(project, 'markComplete')) {
      marked = true;
    }
    if (!marked) {
      marked = safeSet(project, 'completed', true);
    }
    if (date) {
      safeSet(project, 'completionDate', date);
    }
  }

  function completeProject(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) {
      throw new Error('Project not found');
    }
    markProjectComplete(project, params.completionDate || null);
    return projectToJSON(project);
  }

  function deleteTask(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) {
      throw new Error('Task not found');
    }
    var deleted = callIfFunction(task, 'delete') || callIfFunction(task, 'remove');
    if (!deleted) { try { deleteObject(task); deleted = true; } catch (e) {} }
    if (!deleted) { throw new Error('Unable to delete task'); }
    return {id: params.id, deleted: true};
  }

  function deleteProject(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) {
      throw new Error('Project not found');
    }
    var deleted = callIfFunction(project, 'delete') || callIfFunction(project, 'remove');
    if (!deleted) { try { deleteObject(project); deleted = true; } catch (e) {} }
    if (!deleted) { throw new Error('Unable to delete project'); }
    return {id: params.id, deleted: true};
  }

  function deleteTag(params) {
    var doc = getDatabase();
    var tag = findTagById(doc, params.id);
    if (!tag) {
      throw new Error('Tag not found');
    }
    var deleted = callIfFunction(tag, 'delete') || callIfFunction(tag, 'remove');
    if (!deleted) { try { deleteObject(tag); deleted = true; } catch (e) {} }
    if (!deleted) { throw new Error('Unable to delete tag'); }
    return {id: params.id, deleted: true};
  }

  function appendNote(obj, text) {
    if (!text) { return; }
    var existing = safeCall(obj, 'note') || '';
    var separator = existing ? '\n' : '';
    safeSet(obj, 'note', existing + separator + text);
  }

  function uncompleteTask(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var marked = false;
    if (callIfFunction(task, 'markIncomplete')) {
      marked = true;
    }
    if (!marked) {
      safeSet(task, 'completed', false);
    }
    return taskToJSON(task);
  }

  function uncompleteProject(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) { throw new Error('Project not found'); }
    if (typeof Project !== 'undefined' && Project.Status && Project.Status.Active) {
      if (!safeSet(project, 'status', Project.Status.Active)) {
        safeSet(project, 'completed', false);
      }
    } else {
      if (!safeSet(project, 'status', 'active')) {
        safeSet(project, 'completed', false);
      }
    }
    return projectToJSON(project);
  }

  function appendToNote(params) {
    var doc = getDatabase();
    if (params.type === 'project') {
      var project = findProjectById(doc, params.id);
      if (!project) { throw new Error('Project not found'); }
      appendNote(project, params.text);
      return projectToJSON(project);
    } else {
      var task = findTaskById(doc, params.id);
      if (!task) { throw new Error('Task not found'); }
      appendNote(task, params.text);
      return taskToJSON(task);
    }
  }

  function searchTags(params) {
    var doc = getDatabase();
    var query = (params.query || '').toLowerCase();
    var tags = allTags(doc);
    var result = [];
    for (var i = 0; i < tags.length; i++) {
      var name = (safeCall(tags[i], 'name') || '').toLowerCase();
      if (!query || name.indexOf(query) !== -1) {
        result.push(tagToJSON(tags[i]));
      }
    }
    return result;
  }

  function setProjectStatus(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) { throw new Error('Project not found'); }
    var applied = false;
    if (typeof Project !== 'undefined' && Project.Status) {
      var enumMap = {
        'active': Project.Status.Active,
        'on_hold': Project.Status.OnHold,
        'dropped': Project.Status.Dropped
      };
      var enumVal = enumMap[params.status];
      if (enumVal !== undefined) {
        applied = safeSet(project, 'status', enumVal);
      }
    }
    if (!applied) {
      var strMap = {'active': 'active', 'on_hold': 'on hold', 'dropped': 'dropped'};
      var strVal = strMap[params.status];
      if (!strVal) { throw new Error('Invalid status: ' + params.status); }
      applied = safeSet(project, 'status', strVal);
    }
    if (!applied) { throw new Error('Unable to set project status'); }
    return projectToJSON(project);
  }

  function getFolder(params) {
    var doc = getDatabase();
    var folder = null;
    if (params.id) {
      folder = findFolderById(doc, params.id);
    } else if (params.name) {
      folder = findFolderByName(doc, params.name);
    }
    if (!folder) { throw new Error('Folder not found'); }
    var result = folderToJSON(folder);
    result.projects = arrayify(firstValue(folder, ['projects', 'flattenedProjects'])).map(function(p) {
      return safeCall(p, 'name');
    }).filter(function(n) { return n; });
    result.subfolders = arrayify(firstValue(folder, ['folders', 'childFolders'])).map(function(f) {
      return safeCall(f, 'name');
    }).filter(function(n) { return n; });
    return result;
  }

  function updateFolder(params) {
    var doc = getDatabase();
    var folder = findFolderById(doc, params.id);
    if (!folder) { throw new Error('Folder not found'); }
    if (params.name !== undefined) {
      safeSet(folder, 'name', params.name);
    }
    return folderToJSON(folder);
  }

  function deleteFolder(params) {
    var doc = getDatabase();
    var folder = findFolderById(doc, params.id);
    if (!folder) { throw new Error('Folder not found'); }
    var name = safeCall(folder, 'name');
    if (!callIfFunction(folder, 'delete') && !callIfFunction(folder, 'remove')) {
      throw new Error('Unable to delete folder');
    }
    return {id: params.id, deleted: true, name: name};
  }

  function getTaskCounts(params) {
    var doc = getDatabase();
    var tasks = allTasks(doc);
    var inboxItems = arrayify(firstValue(doc, ['inboxTasks', 'inbox', 'inboxItems']));
    var total = 0, available = 0, completed = 0, overdue = 0, flagged = 0;
    for (var i = 0; i < tasks.length; i++) {
      var task = tasks[i];
      total++;
      if (!!safeCall(task, 'completed')) { completed++; continue; }
      if (isTaskAvailable(task)) { available++; }
      if (isTaskOverdue(task)) { overdue++; }
      if (!!safeCall(task, 'flagged')) { flagged++; }
    }
    return {total: total, available: available, completed: completed, overdue: overdue, flagged: flagged, inbox: inboxItems.length};
  }

  function getProjectCounts(params) {
    var doc = getDatabase();
    var projects = allProjects(doc);
    var total = 0, active = 0, onHold = 0, dropped = 0, stalled = 0;
    for (var i = 0; i < projects.length; i++) {
      var project = projects[i];
      total++;
      var status = normalizeStatus(String(firstValue(project, ['status', 'projectStatus']) || ''));
      if (status === 'active') {
        active++;
        var ptasks = arrayify(firstValue(project, ['tasks', 'flattenedTasks']));
        var hasAvailable = false;
        for (var j = 0; j < ptasks.length; j++) {
          if (!safeCall(ptasks[j], 'completed') && isTaskAvailable(ptasks[j])) {
            hasAvailable = true;
            break;
          }
        }
        if (!hasAvailable) { stalled++; }
      } else if (status === 'dropped') {
        dropped++;
      } else if (status === 'on_hold') {
        onHold++;
      }
    }
    return {total: total, active: active, on_hold: onHold, dropped: dropped, stalled: stalled};
  }

  function getForecast(params) {
    var doc = getDatabase();
    var tasks = allTasks(doc);
    var now = new Date();
    var todayEnd = new Date(now.getFullYear(), now.getMonth(), now.getDate(), 23, 59, 59, 999);
    var weekEnd = new Date(now.getTime() + 7 * 24 * 60 * 60 * 1000);
    var overdue = [], today = [], flagged = [], dueThisWeek = [];
    for (var i = 0; i < tasks.length; i++) {
      var task = tasks[i];
      if (!!safeCall(task, 'completed')) { continue; }
      var dueDate = dateValue(firstValue(task, ['dueDate']));
      if (dueDate) {
        if (dueDate.getTime() < now.getTime()) {
          overdue.push(taskToJSON(task));
        } else if (dueDate.getTime() <= todayEnd.getTime()) {
          today.push(taskToJSON(task));
        } else if (dueDate.getTime() <= weekEnd.getTime()) {
          dueThisWeek.push(taskToJSON(task));
        }
      }
      if (!!safeCall(task, 'flagged')) { flagged.push(taskToJSON(task)); }
    }
    return {overdue: overdue, today: today, flagged: flagged, dueThisWeek: dueThisWeek};
  }

  function createSubtask(params) {
    var doc = getDatabase();
    var parent = findTaskById(doc, params.parentId);
    if (!parent) { throw new Error('Parent task not found'); }
    var task = null;
    if (typeof Task !== 'undefined') {
      try { task = new Task(params.name, parent); } catch (e) {}
    }
    if (!task && typeof parent.make === 'function') {
      try { task = parent.make({new: 'task', withProperties: {name: params.name}}); } catch (e) {}
    }
    if (!task) { throw new Error('Unable to create subtask'); }
    applyCommonTaskFields(task, params, doc);
    return taskToJSON(task);
  }

  function duplicateTask(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var project = firstValue(task, ['containingProject', 'project']);
    var newParams = {
      name: params.name || safeCall(task, 'name'),
      note: safeCall(task, 'note'),
      flagged: safeCall(task, 'flagged'),
      due: toISO(firstValue(task, ['dueDate'])),
      defer: toISO(firstValue(task, ['deferDate'])),
      estimatedMinutes: safeCall(task, 'estimatedMinutes'),
      tags: tagNames(task),
      createMissingTags: false
    };
    if (project) {
      newParams.project = safeCall(project, 'name');
      newParams.createMissingProject = false;
    }
    return createTask(newParams);
  }

  function createTasksBatch(params) {
    var tasks = params.tasks || [];
    var result = [];
    for (var i = 0; i < tasks.length; i++) {
      result.push(createTask(tasks[i]));
    }
    return result;
  }

  function deleteTasksBatch(params) {
    var doc = getDatabase();
    var ids = params.ids || [];
    var seen = {};
    var unique = [];
    for (var i = 0; i < ids.length; i++) {
      if (!seen[ids[i]]) { seen[ids[i]] = true; unique.push(ids[i]); }
    }
    var deleted = [];
    var errors = [];
    for (var j = 0; j < unique.length; j++) {
      try {
        var task = findTaskById(doc, unique[j]);
        if (!task) { errors.push({id: unique[j], error: 'Task not found'}); continue; }
        var ok = callIfFunction(task, 'delete') || callIfFunction(task, 'remove');
        if (!ok) { try { deleteObject(task); ok = true; } catch (e) {} }
        if (ok) { deleted.push(unique[j]); }
        else { errors.push({id: unique[j], error: 'Delete failed'}); }
      } catch (e) {
        errors.push({id: unique[j], error: e.message || String(e)});
      }
    }
    var result = {deleted: deleted.length, ids: deleted};
    if (errors.length > 0) { result.errors = errors; }
    return result;
  }

  function moveTasksBatch(params) {
    var doc = getDatabase();
    var project = findProjectByName(doc, params.project);
    if (!project) { throw new Error('Project not found'); }
    var result = [];
    var errors = [];
    var ids = params.ids || [];
    for (var i = 0; i < ids.length; i++) {
      var task = findTaskById(doc, ids[i]);
      if (!task) { errors.push({id: ids[i], error: 'Task not found'}); continue; }
      try {
        assignTaskToProject(task, project);
        result.push(taskToJSON(task));
      } catch (e) {
        errors.push({id: ids[i], error: e.message || String(e)});
      }
    }
    var out = {moved: result.length, tasks: result};
    if (errors.length > 0) { out.errors = errors; }
    return out;
  }

  function listNotifications(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var alarms = arrayify(firstValue(task, ['alarms', 'alerts', 'notifications']));
    return alarms.map(function(alarm) {
      return {
        id: idValue(alarm),
        kind: safeCall(alarm, 'kind') || safeCall(alarm, 'type'),
        fireDate: toISO(firstValue(alarm, ['absoluteFireDate', 'fireDate', 'date'])),
        repeatInterval: safeCall(alarm, 'repeatInterval'),
        isSnoozed: safeCall(alarm, 'isSnoozed'),
        usesFloatingTimeZone: safeCall(alarm, 'usesFloatingTimeZone'),
        relativeFireOffset: safeCall(alarm, 'relativeFireOffset')
      };
    });
  }

  function addNotification(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var fireDate = parseDate(params.date);
    if (!fireDate) { throw new Error('Invalid date'); }
    var alarm = null;
    if (typeof Alarm !== 'undefined' && typeof Alarm.byAbsoluteDateWithTask === 'function') {
      try { alarm = Alarm.byAbsoluteDateWithTask(fireDate, task); } catch (e) {}
    }
    if (!alarm && task && typeof task.make === 'function') {
      try { alarm = task.make({new: 'alarm', withProperties: {absoluteFireDate: fireDate}}); } catch (e) {}
    }
    if (!alarm) { throw new Error('Unable to create notification'); }
    return {
      id: idValue(alarm),
      kind: safeCall(alarm, 'kind'),
      fireDate: toISO(firstValue(alarm, ['absoluteFireDate', 'fireDate']))
    };
  }

  function removeNotification(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var alarms = arrayify(firstValue(task, ['alarms', 'alerts', 'notifications']));
    var targetId = normalizeId(params.notificationId);
    for (var i = 0; i < alarms.length; i++) {
      if (idValue(alarms[i]) === targetId) {
        if (!callIfFunction(alarms[i], 'delete') && !callIfFunction(alarms[i], 'remove')) {
          throw new Error('Unable to remove notification');
        }
        return {deleted: true, notificationId: params.notificationId};
      }
    }
    throw new Error('Notification not found');
  }

  function setTaskRepetition(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    if (params.rule === null || params.rule === undefined || params.rule === '') {
      safeSet(task, 'repetitionRule', null);
      safeSet(task, 'recurrenceRule', null);
      return taskToJSON(task);
    }
    var applied = false;
    if (typeof Task !== 'undefined' && Task.RepetitionRule && Task.RepetitionMethod) {
      try {
        var methodMap = {
          'fixed': Task.RepetitionMethod.Fixed,
          'due': Task.RepetitionMethod.DueDate,
          'defer': Task.RepetitionMethod.DeferDate
        };
        var method = methodMap[params.scheduleType || 'due'] || Task.RepetitionMethod.DueDate;
        var rule = new Task.RepetitionRule(params.rule, method);
        applied = safeSet(task, 'repetitionRule', rule);
      } catch (e) {}
    }
    if (!applied) {
      if (!safeSet(task, 'repetitionRule', params.rule)) {
        safeSet(task, 'recurrenceRule', params.rule);
      }
      applied = true;
    }
    if (params.scheduleType) {
      var strMap = {'fixed': 'fixed', 'due': 'due date', 'defer': 'defer date'};
      safeSet(task, 'repetitionMethod', strMap[params.scheduleType] || params.scheduleType);
    }
    if (params.anchorDateKey !== undefined && typeof Task !== 'undefined' && Task.AnchorDateKey) {
      try {
        var anchorMap = {
          'due': Task.AnchorDateKey.Due,
          'defer': Task.AnchorDateKey.Defer,
          'planned': Task.AnchorDateKey.Planned
        };
        var anchor = anchorMap[params.anchorDateKey];
        if (anchor !== undefined) { safeSet(task, 'anchorDateKey', anchor); }
      } catch (e) {}
    }
    if (params.catchUpAutomatically !== undefined) {
      safeSet(task, 'catchUpAutomatically', params.catchUpAutomatically);
    }
    return taskToJSON(task);
  }

  function markReviewed(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) { throw new Error('Project not found'); }
    if (callIfFunction(project, 'markReviewed')) {
      return projectToJSON(project);
    }
    safeSet(project, 'lastReviewDate', new Date());
    return projectToJSON(project);
  }

  function dropTask(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    if (callIfFunction(task, 'drop', [false])) {
      return taskToJSON(task);
    }
    if (!safeSet(task, 'dropped', true)) {
      throw new Error('Unable to drop task — operation not supported in this OmniFocus version');
    }
    return taskToJSON(task);
  }

  function importTaskpaper(params) {
    var doc = getDatabase();
    var text = params.text;
    if (!text) { throw new Error('Missing text parameter'); }
    var target = null;
    if (params.project) {
      target = findProjectByName(doc, params.project);
      if (!target) { throw new Error('Project not found'); }
    }
    var tasks = [];
    try {
      if (typeof Task !== 'undefined' && typeof Task.byParsingTransportText === 'function') {
        var parsed = Task.byParsingTransportText(text, target || false);
        tasks = arrayify(parsed).map(taskToJSON);
      } else {
        // Fallback: line-by-line
        var lines = text.split('\n');
        for (var i = 0; i < lines.length; i++) {
          var line = lines[i].replace(/^[\s-]*/, '');
          if (!line) { continue; }
          var t = null;
          if (typeof Task !== 'undefined') {
            try { t = new Task(line, target || null); } catch (e) {}
          }
          if (t) { tasks.push(taskToJSON(t)); }
        }
      }
    } catch (e) {
      throw new Error('Unable to import TaskPaper text: ' + e.message);
    }
    return {imported: tasks.length, tasks: tasks};
  }

  function addRelativeNotification(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var offset = -(params.beforeSeconds || 0);
    var alarm = null;
    if (typeof Alarm !== 'undefined' && typeof Alarm.byRelativeOffsetWithTask === 'function') {
      try { alarm = Alarm.byRelativeOffsetWithTask(offset, task); } catch (e) {}
    }
    if (!alarm && task && typeof task.addNotification === 'function') {
      try { alarm = task.addNotification(offset); } catch (e) {}
    }
    if (!alarm) { throw new Error('Unable to create relative notification'); }
    return {
      id: idValue(alarm),
      kind: safeCall(alarm, 'kind'),
      relativeFireOffset: safeCall(alarm, 'relativeFireOffset')
    };
  }

  function moveTag(params) {
    var doc = getDatabase();
    var tag = findTagById(doc, params.id);
    if (!tag) { throw new Error('Tag not found'); }
    if (params.parentTag) {
      var parent = findTagByName(doc, params.parentTag);
      if (!parent) { throw new Error('Parent tag not found'); }
      try {
        if (typeof moveTags === 'function') { moveTags([tag], parent); }
        else { safeSet(tag, 'parent', parent); }
      } catch (e) { throw new Error('Unable to move tag: ' + e.message); }
    } else {
      try {
        if (typeof moveTags === 'function') { moveTags([tag], null); }
        else { safeSet(tag, 'parent', null); }
      } catch (e) { throw new Error('Unable to move tag to root: ' + e.message); }
    }
    return tagToJSON(tag);
  }

  function moveFolder(params) {
    var doc = getDatabase();
    var folder = findFolderById(doc, params.id);
    if (!folder) { throw new Error('Folder not found'); }
    if (params.parentFolder) {
      var parent = findFolderByName(doc, params.parentFolder);
      if (!parent) { throw new Error('Parent folder not found'); }
      try {
        if (typeof moveSections === 'function') { moveSections([folder], parent); }
        else { safeSet(folder, 'parent', parent); }
      } catch (e) { throw new Error('Unable to move folder: ' + e.message); }
    } else {
      try {
        if (typeof moveSections === 'function') { moveSections([folder], null); }
        else { safeSet(folder, 'parent', null); }
      } catch (e) { throw new Error('Unable to move folder to root: ' + e.message); }
    }
    return folderToJSON(folder);
  }

  function convertToProject(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    try {
      if (typeof convertTasksToProjects === 'function') {
        var projects = convertTasksToProjects([task], doc);
        if (projects && projects.length > 0) {
          return projectToJSON(projects[0]);
        }
      }
      if (doc && typeof doc.convertTasksToProjects === 'function') {
        var projects2 = doc.convertTasksToProjects([task]);
        if (projects2 && projects2.length > 0) {
          return projectToJSON(projects2[0]);
        }
      }
    } catch (e) {}
    // Fallback: manual copy+delete
    var name = safeCall(task, 'name');
    var project = null;
    if (typeof Project !== 'undefined') {
      try { project = new Project(name); } catch (e) {}
    }
    if (!project) { throw new Error('Unable to convert task to project'); }
    safeSet(project, 'note', safeCall(task, 'note'));
    safeSet(project, 'flagged', safeCall(task, 'flagged'));
    var due = firstValue(task, ['dueDate']);
    if (due) { safeSet(project, 'dueDate', due); }
    var defer = firstValue(task, ['deferDate']);
    if (defer) { safeSet(project, 'deferDate', defer); }
    var deleted = callIfFunction(task, 'delete') || callIfFunction(task, 'remove');
    var result = projectToJSON(project);
    if (!deleted) { result.warning = 'Original task could not be deleted'; }
    return result;
  }

  function duplicateProject(params) {
    var doc = getDatabase();
    var project = findProjectById(doc, params.id);
    if (!project) { throw new Error('Project not found'); }
    var newName = params.name || (safeCall(project, 'name') + ' (copy)');
    try {
      if (typeof duplicateSections === 'function') {
        var dups = duplicateSections([project]);
        if (dups && dups.length > 0) {
          safeSet(dups[0], 'name', newName);
          return projectToJSON(dups[0]);
        }
      }
      if (doc && typeof doc.duplicateSections === 'function') {
        var dups2 = doc.duplicateSections([project]);
        if (dups2 && dups2.length > 0) {
          safeSet(dups2[0], 'name', newName);
          return projectToJSON(dups2[0]);
        }
      }
    } catch (e) {}
    // Fallback: manual copy
    var newProject = null;
    if (typeof Project !== 'undefined') {
      try { newProject = new Project(newName); } catch (e) {}
    }
    if (!newProject) { throw new Error('Unable to duplicate project'); }
    safeSet(newProject, 'note', safeCall(project, 'note'));
    safeSet(newProject, 'flagged', safeCall(project, 'flagged'));
    var due = firstValue(project, ['dueDate']);
    if (due) { safeSet(newProject, 'dueDate', due); }
    var defer = firstValue(project, ['deferDate']);
    if (defer) { safeSet(newProject, 'deferDate', defer); }
    return projectToJSON(newProject);
  }

  function getForecastTag(params) {
    try {
      if (typeof Tag !== 'undefined' && Tag.forecastTag) {
        var ft = Tag.forecastTag;
        if (ft) { return tagToJSON(ft); }
      }
    } catch (e) {}
    return null;
  }

  function cleanUp(params) {
    try {
      if (typeof document !== 'undefined' && document && typeof document.cleanUp === 'function') {
        document.cleanUp();
        return {success: true};
      }
    } catch (e) {}
    return {success: true, note: 'cleanUp not available'};
  }

  function getSettings(params) {
    var result = {backend: 'automation'};
    try {
      if (typeof Settings !== 'undefined') {
        var keys = params.keys || [];
        if (keys.length === 0) {
          result.note = 'Pass specific setting keys to retrieve values';
        } else {
          for (var i = 0; i < keys.length; i++) {
            try {
              var val = Settings.objectForKey(keys[i]);
              result[keys[i]] = val !== null && val !== undefined ? String(val) : null;
            } catch (e) { result[keys[i]] = null; }
          }
        }
      } else if (typeof settings !== 'undefined') {
        var keys2 = params.keys || [];
        for (var j = 0; j < keys2.length; j++) {
          try {
            result[keys2[j]] = String(safeCall(settings, keys2[j]));
          } catch (e) { result[keys2[j]] = null; }
        }
      }
    } catch (e) {}
    return result;
  }

  function listLinkedFiles(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var urls = [];
    try {
      var linked = arrayify(firstValue(task, ['linkedFileURLs', 'attachments']));
      for (var i = 0; i < linked.length; i++) {
        var u = linked[i];
        urls.push(typeof u === 'string' ? u : String(u));
      }
    } catch (e) {}
    return {id: params.id, linkedFileURLs: urls};
  }

  function addLinkedFile(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    try {
      if (typeof task.addLinkedFileURL === 'function') {
        task.addLinkedFileURL(URL.fromString(params.url));
      } else {
        safeSet(task, 'linkedFileURLs', arrayify(safeCall(task, 'linkedFileURLs')).concat([URL.fromString(params.url)]));
      }
    } catch (e) { throw new Error('Unable to add linked file: ' + e.message); }
    return {success: true, url: params.url};
  }

  function removeLinkedFile(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    try {
      if (typeof task.removeLinkedFileWithURL === 'function') {
        task.removeLinkedFileWithURL(URL.fromString(params.url));
      } else {
        var current = arrayify(safeCall(task, 'linkedFileURLs'));
        var filtered = current.filter(function(u) { return String(u) !== params.url; });
        safeSet(task, 'linkedFileURLs', filtered);
      }
    } catch (e) { throw new Error('Unable to remove linked file: ' + e.message); }
    return {success: true, url: params.url};
  }

  function searchProjects(params) {
    var doc = getDatabase();
    var q = params.query || '';
    var results = [];
    try {
      if (typeof doc.projectsMatching === 'function') {
        var matched = arrayify(doc.projectsMatching(q));
        for (var i = 0; i < matched.length; i++) {
          results.push(projectToJSON(matched[i]));
        }
        return results;
      }
    } catch (e) {}
    var ql = q.toLowerCase();
    var projects = arrayify(firstValue(doc, ['flattenedProjects', 'projects']));
    for (var i = 0; i < projects.length; i++) {
      var name = safeCall(projects[i], 'name') || '';
      if (name.toLowerCase().indexOf(ql) >= 0) {
        results.push(projectToJSON(projects[i]));
      }
    }
    return results;
  }

  function searchFolders(params) {
    var doc = getDatabase();
    var q = params.query || '';
    var results = [];
    try {
      if (typeof doc.foldersMatching === 'function') {
        var matched = arrayify(doc.foldersMatching(q));
        for (var i = 0; i < matched.length; i++) {
          results.push(folderToJSON(matched[i]));
        }
        return results;
      }
    } catch (e) {}
    var ql = q.toLowerCase();
    var folders = [];
    collectFoldersFrom(doc, folders, {});
    for (var i = 0; i < folders.length; i++) {
      var name = safeCall(folders[i], 'name') || '';
      if (name.toLowerCase().indexOf(ql) >= 0) {
        results.push(folderToJSON(folders[i]));
      }
    }
    return results;
  }

  function searchTasksNative(params) {
    var doc = getDatabase();
    var q = params.query || '';
    try {
      if (typeof doc.tasksMatching === 'function') {
        var matched = arrayify(doc.tasksMatching(q));
        var results = [];
        for (var i = 0; i < matched.length; i++) {
          results.push(taskToJSON(matched[i]));
        }
        return results;
      }
    } catch (e) {}
    return searchTasks(params);
  }

  function lookupUrl(params) {
    var doc = getDatabase();
    try {
      if (typeof doc.objectForURL === 'function') {
        var url = URL.fromString(params.url);
        var obj = doc.objectForURL(url);
        if (!obj) { return {found: false}; }
        var typeName = '';
        try { typeName = obj.constructor ? obj.constructor.name : ''; } catch (e) {}
        if (typeName === 'Task' || safeCall(obj, 'taskStatus') !== null) {
          return {found: true, type: 'task', object: taskToJSON(obj)};
        }
        if (typeName === 'Project' || safeCall(obj, 'containsSingletonActions') !== null) {
          return {found: true, type: 'project', object: projectToJSON(obj)};
        }
        if (typeName === 'Tag' || safeCall(obj, 'allowsNextAction') !== null) {
          return {found: true, type: 'tag', object: tagToJSON(obj)};
        }
        if (typeName === 'Folder') {
          return {found: true, type: 'folder', object: folderToJSON(obj)};
        }
        return {found: true, type: typeName || 'unknown', id: idValue(obj), name: safeCall(obj, 'name')};
      }
    } catch (e) {}
    return {error: 'URL lookup not available', url: params.url};
  }

  function getForecastDays(params) {
    var count = params.count || 14;
    var results = [];
    try {
      if (typeof ForecastDay !== 'undefined') {
        var day = ForecastDay.today;
        for (var i = 0; i < count && day; i++) {
          results.push({
            date: toISO(safeCall(day, 'date')),
            name: safeCall(day, 'name'),
            kind: safeCall(day, 'kind') ? String(safeCall(day, 'kind')) : null,
            badgeCount: safeCall(day, 'badgeCount'),
            deferredCount: safeCall(day, 'deferredCount')
          });
          try { var nextDay = (day && typeof day.next === 'function') ? day.next() : null; day = nextDay; } catch (e) { day = null; }
        }
        return {days: results};
      }
    } catch (e) {}
    return getForecast(params);
  }

  function getFocus(params) {
    var results = [];
    try {
      if (typeof document !== 'undefined' && safeCall(document, 'focus')) {
        var focused = arrayify(safeCall(document, 'focus'));
        for (var i = 0; i < focused.length; i++) {
          results.push({id: idValue(focused[i]), name: safeCall(focused[i], 'name')});
        }
      }
    } catch (e) {}
    return {focused: results};
  }

  function setFocus(params) {
    var doc = getDatabase();
    var ids = params.ids || [];
    try {
      if (ids.length === 0) {
        if (typeof document !== 'undefined' && typeof document.unfocus === 'function') {
          document.unfocus();
        }
        return {success: true, focused: []};
      }
      var objects = [];
      for (var i = 0; i < ids.length; i++) {
        var proj = findProjectById(doc, ids[i]);
        if (proj) { objects.push(proj); continue; }
        var folder = findFolderById(doc, ids[i]);
        if (folder) { objects.push(folder); }
      }
      if (typeof document !== 'undefined' && typeof document.focus === 'function') {
        document.focus(objects);
      }
      return {success: true, focused: objects.map(function(o) { return {id: idValue(o), name: safeCall(o, 'name')}; })};
    } catch (e) { throw new Error('Unable to set focus: ' + e.message); }
  }

  function undoAction(params) {
    try {
      if (typeof document !== 'undefined' && typeof document.undo === 'function') {
        document.undo();
        return {success: true, canUndo: safeCall(document, 'canUndo'), canRedo: safeCall(document, 'canRedo')};
      }
    } catch (e) {}
    return {error: 'Undo not available'};
  }

  function redoAction(params) {
    try {
      if (typeof document !== 'undefined' && typeof document.redo === 'function') {
        document.redo();
        return {success: true, canUndo: safeCall(document, 'canUndo'), canRedo: safeCall(document, 'canRedo')};
      }
    } catch (e) {}
    return {error: 'Redo not available'};
  }

  function saveAction(params) {
    try {
      if (typeof document !== 'undefined' && typeof document.save === 'function') {
        document.save();
      }
    } catch (e) {}
    return {success: true};
  }

  function duplicateTasksBatch(params) {
    var doc = getDatabase();
    var ids = params.ids || [];
    var results = [];
    var errors = [];
    for (var i = 0; i < ids.length; i++) {
      var task = findTaskById(doc, ids[i]);
      if (task) {
        try {
          var dup = null;
          if (typeof duplicateTasks === 'function') {
            var dups = duplicateTasks([task], task.parent || task.containingProject);
            dup = dups && dups.length > 0 ? dups[0] : null;
          }
          if (!dup && typeof task.duplicate === 'function') {
            dup = task.duplicate();
          }
          if (dup) { results.push(taskToJSON(dup)); }
        } catch (e) {
          errors.push({id: ids[i], error: e.message || String(e)});
        }
      }
    }
    var result = {duplicated: results.length, tasks: results};
    if (errors.length > 0) { result.errors = errors; }
    return result;
  }

  function duplicateTagsAction(params) {
    var doc = getDatabase();
    var ids = params.ids || [];
    var results = [];
    for (var i = 0; i < ids.length; i++) {
      var tag = findTagById(doc, ids[i]);
      if (tag) {
        try {
          var dup = null;
          if (typeof duplicateTags === 'function') {
            var dups = duplicateTags([tag]);
            dup = dups && dups.length > 0 ? dups[0] : null;
          }
          if (!dup) {
            dup = new Tag(safeCall(tag, 'name') + ' Copy');
          }
          if (dup) { results.push(tagToJSON(dup)); }
        } catch (e) {
          results.push({error: 'Failed to duplicate tag ' + ids[i] + ': ' + e.message});
        }
      }
    }
    return {duplicated: results.length, tags: results};
  }

  function moveProjectsBatch(params) {
    var doc = getDatabase();
    var ids = params.ids || [];
    var targetFolder = null;
    if (params.folder) {
      targetFolder = findFolderByName(doc, params.folder);
      if (!targetFolder) { throw new Error('Folder not found: ' + params.folder); }
    }
    var results = [];
    var projects = [];
    for (var i = 0; i < ids.length; i++) {
      var project = findProjectById(doc, ids[i]);
      if (project) { projects.push(project); }
    }
    try {
      if (targetFolder && typeof moveSections === 'function') {
        moveSections(projects, targetFolder);
      } else if (targetFolder) {
        for (var j = 0; j < projects.length; j++) {
          safeSet(projects[j], 'parentFolder', targetFolder);
        }
      }
    } catch (e) {
      throw new Error('Failed to move projects: ' + e.message);
    }
    for (var k = 0; k < projects.length; k++) {
      results.push(projectToJSON(projects[k]));
    }
    return {moved: results.length, projects: results};
  }

  function reorderTaskTags(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var tagIds = params.tagIds || [];
    // Resolve all tags first before clearing
    var newTags = [];
    var missing = [];
    for (var i = 0; i < tagIds.length; i++) {
      var tag = findTagById(doc, tagIds[i]);
      if (tag) { newTags.push(tag); } else { missing.push(tagIds[i]); }
    }
    if (missing.length > 0) {
      throw new Error('Tags not found: ' + missing.join(', '));
    }
    // Save original tags for rollback
    var origTags = [];
    try { origTags = arrayify(task.tags); } catch (e) {}
    // Clear then set — avoid applyTags fallback path which appends instead of replacing
    var cleared = safeSet(task, 'tags', []);
    if (!cleared) {
      // Fallback: remove tags individually
      try {
        var current = arrayify(task.tags);
        for (var ri = 0; ri < current.length; ri++) {
          try { if (typeof task.removeTag === 'function') { task.removeTag(current[ri]); } } catch (e) {}
        }
      } catch (e) {}
    }
    var applied = safeSet(task, 'tags', newTags);
    if (!applied) {
      // Fallback: add tags individually
      var addedCount = 0;
      for (var ai = 0; ai < newTags.length; ai++) {
        try {
          if (typeof task.addTag === 'function') { task.addTag(newTags[ai]); addedCount++; }
        } catch (e) {}
      }
      if (addedCount === 0 && newTags.length > 0) {
        // Total failure — rollback
        try { safeSet(task, 'tags', origTags); } catch (e2) {}
        throw new Error('Failed to reorder tags: unable to apply new tag list');
      }
    }
    return taskToJSON(task);
  }

  function copyTasksAction(params) {
    var doc = getDatabase();
    var ids = params.ids || [];
    var tasks = [];
    for (var i = 0; i < ids.length; i++) {
      var task = findTaskById(doc, ids[i]);
      if (task) { tasks.push(task); }
    }
    try {
      if (typeof copyTasksToPasteboard === 'function') {
        copyTasksToPasteboard(tasks);
        return {success: true, count: tasks.length};
      }
      if (typeof Pasteboard !== 'undefined' && typeof Pasteboard.general !== 'undefined') {
        Pasteboard.general.tasks = tasks;
        return {success: true, count: tasks.length};
      }
    } catch (e) {}
    return {error: 'Copy to pasteboard not available'};
  }

  function pasteTasksAction(params) {
    var doc = getDatabase();
    try {
      var project = params.project ? findProjectByName(doc, params.project) : null;
      if (typeof pasteTasksFromPasteboard === 'function') {
        var pasted = pasteTasksFromPasteboard(project);
        var results = arrayify(pasted).map(function(t) { return taskToJSON(t); });
        return {success: true, tasks: results};
      }
    } catch (e) {}
    return {error: 'Paste from pasteboard not available'};
  }

  function nextRepetitionDate(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var rule = safeCall(task, 'repetitionRule');
    if (!rule) { return {nextDate: null, note: 'No repetition rule set'}; }
    try {
      var afterDate = params.afterDate ? parseDate(params.afterDate) : new Date();
      if (typeof rule.firstDateAfterDate === 'function') {
        var next = rule.firstDateAfterDate(afterDate);
        return {nextDate: toISO(next)};
      }
    } catch (e) {}
    return {nextDate: null, note: 'Unable to compute next repetition date'};
  }

  function setForecastTagAction(params) {
    try {
      if (typeof Tag !== 'undefined' && Tag.forecastTag !== undefined) {
        if (params.id === null || params.id === '') {
          Tag.forecastTag = null;
          return {success: true, forecastTag: null};
        }
        var doc = getDatabase();
        var tag = findTagById(doc, params.id);
        if (!tag) { throw new Error('Tag not found'); }
        Tag.forecastTag = tag;
        return {success: true, forecastTag: tagToJSON(tag)};
      }
    } catch (e) { throw new Error('Unable to set forecast tag: ' + e.message); }
    return {error: 'Forecast tag setting not available'};
  }

  function setNotificationRepeat(params) {
    var doc = getDatabase();
    var task = findTaskById(doc, params.id);
    if (!task) { throw new Error('Task not found'); }
    var alarms = arrayify(firstValue(task, ['alarms', 'alerts', 'notifications']));
    var targetId = normalizeId(params.notificationId);
    for (var i = 0; i < alarms.length; i++) {
      if (idValue(alarms[i]) === targetId) {
        safeSet(alarms[i], 'repeatInterval', params.repeatInterval || 0);
        return {success: true, notificationId: params.notificationId, repeatInterval: params.repeatInterval};
      }
    }
    throw new Error('Notification not found');
  }

  function encodeResult(value) {
    if (value === undefined) {
      return 'null';
    }
    try {
      return JSON.stringify(value);
    } catch (e) {
      return JSON.stringify(String(value));
    }
  }

  var input = JSON.parse(__OF_INPUT_JSON__);
  var action = input.action;
  var params = input.params || {};
  var result = null;

  switch (action) {
    case 'list_tasks':
      result = listTasks(params);
      break;
    case 'list_inbox':
      result = listInbox();
      break;
    case 'list_projects':
      result = listProjects();
      break;
    case 'list_tags':
      result = listTags();
      break;
    case 'list_perspectives':
      result = listPerspectives();
      break;
    case 'list_folders':
      result = listFolders(params);
      break;
    case 'create_folder':
      result = createFolder(params);
      break;
    case 'move_project':
      result = moveProject(params);
      break;
    case 'list_flagged':
      result = listFlagged(params);
      break;
    case 'list_overdue':
      result = listOverdue(params);
      break;
    case 'list_available':
      result = listAvailable(params);
      break;
    case 'search_tasks':
      result = searchTasks(params);
      break;
    case 'list_task_children':
      result = listTaskChildren(params);
      break;
    case 'get_task_parent':
      result = getTaskParent(params);
      break;
    case 'get_task':
      result = getTask(params);
      break;
    case 'get_project':
      result = getProject(params);
      break;
    case 'get_tag':
      result = getTag(params);
      break;
    case 'create_task':
      result = createTask(params);
      break;
    case 'create_project':
      result = createProject(params);
      break;
    case 'create_tag':
      result = createTag(params);
      break;
    case 'update_task':
      result = updateTask(params);
      break;
    case 'set_project_sequential':
      result = setProjectSequential(params);
      break;
    case 'process_inbox':
      result = processInbox(params);
      break;
    case 'update_project':
      result = updateProject(params);
      break;
    case 'update_tag':
      result = updateTag(params);
      break;
    case 'complete_task':
      result = completeTask(params);
      break;
    case 'complete_project':
      result = completeProject(params);
      break;
    case 'delete_task':
      result = deleteTask(params);
      break;
    case 'delete_project':
      result = deleteProject(params);
      break;
    case 'delete_tag':
      result = deleteTag(params);
      break;
    case 'uncomplete_task':
      result = uncompleteTask(params);
      break;
    case 'uncomplete_project':
      result = uncompleteProject(params);
      break;
    case 'append_to_note':
      result = appendToNote(params);
      break;
    case 'search_tags':
      result = searchTags(params);
      break;
    case 'set_project_status':
      result = setProjectStatus(params);
      break;
    case 'get_folder':
      result = getFolder(params);
      break;
    case 'update_folder':
      result = updateFolder(params);
      break;
    case 'delete_folder':
      result = deleteFolder(params);
      break;
    case 'get_task_counts':
      result = getTaskCounts(params);
      break;
    case 'get_project_counts':
      result = getProjectCounts(params);
      break;
    case 'get_forecast':
      result = getForecast(params);
      break;
    case 'create_subtask':
      result = createSubtask(params);
      break;
    case 'duplicate_task':
      result = duplicateTask(params);
      break;
    case 'create_tasks_batch':
      result = createTasksBatch(params);
      break;
    case 'delete_tasks_batch':
      result = deleteTasksBatch(params);
      break;
    case 'move_tasks_batch':
      result = moveTasksBatch(params);
      break;
    case 'list_notifications':
      result = listNotifications(params);
      break;
    case 'add_notification':
      result = addNotification(params);
      break;
    case 'remove_notification':
      result = removeNotification(params);
      break;
    case 'set_task_repetition':
      result = setTaskRepetition(params);
      break;
    case 'mark_reviewed':
      result = markReviewed(params);
      break;
    case 'drop_task':
      result = dropTask(params);
      break;
    case 'import_taskpaper':
      result = importTaskpaper(params);
      break;
    case 'add_relative_notification':
      result = addRelativeNotification(params);
      break;
    case 'move_tag':
      result = moveTag(params);
      break;
    case 'move_folder':
      result = moveFolder(params);
      break;
    case 'convert_to_project':
      result = convertToProject(params);
      break;
    case 'duplicate_project':
      result = duplicateProject(params);
      break;
    case 'get_forecast_tag':
      result = getForecastTag(params);
      break;
    case 'clean_up':
      result = cleanUp(params);
      break;
    case 'get_settings':
      result = getSettings(params);
      break;
    case 'list_linked_files':
      result = listLinkedFiles(params);
      break;
    case 'add_linked_file':
      result = addLinkedFile(params);
      break;
    case 'remove_linked_file':
      result = removeLinkedFile(params);
      break;
    case 'search_projects':
      result = searchProjects(params);
      break;
    case 'search_folders':
      result = searchFolders(params);
      break;
    case 'search_tasks_native':
      result = searchTasksNative(params);
      break;
    case 'lookup_url':
      result = lookupUrl(params);
      break;
    case 'get_forecast_days':
      result = getForecastDays(params);
      break;
    case 'get_focus':
      result = getFocus(params);
      break;
    case 'set_focus':
      result = setFocus(params);
      break;
    case 'undo':
      result = undoAction(params);
      break;
    case 'redo':
      result = redoAction(params);
      break;
    case 'save':
      result = saveAction(params);
      break;
    case 'duplicate_tasks_batch':
      result = duplicateTasksBatch(params);
      break;
    case 'duplicate_tags':
      result = duplicateTagsAction(params);
      break;
    case 'move_projects_batch':
      result = moveProjectsBatch(params);
      break;
    case 'reorder_task_tags':
      result = reorderTaskTags(params);
      break;
    case 'copy_tasks':
      result = copyTasksAction(params);
      break;
    case 'paste_tasks':
      result = pasteTasksAction(params);
      break;
    case 'next_repetition_date':
      result = nextRepetitionDate(params);
      break;
    case 'set_forecast_tag':
      result = setForecastTagAction(params);
      break;
    case 'set_notification_repeat':
      result = setNotificationRepeat(params);
      break;
    default:
      throw new Error('Unknown action: ' + action);
  }

  return encodeResult(result);
})();
"""#

@main
struct OmniFocusMCPServer {
    static func main() {
        let server = MCPServer()
        server.run()
    }
}

private final class MCPServer {
    private let tools: [ToolDefinition] = [
        ToolDefinition(
            name: "omnifocus_list_tasks",
            description: "List tasks with optional filters.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "status": ["type": "string", "enum": ["all", "available", "completed"]],
                    "project": ["type": "string"],
                    "tag": ["type": "string"],
                    "search": ["type": "string"],
                    "flagged": ["type": "boolean"],
                    "limit": ["type": "integer", "minimum": 1]
                ]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_inbox",
            description: "List tasks in the OmniFocus inbox.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_projects",
            description: "List all projects.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_tags",
            description: "List all tags.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_perspectives",
            description: "List all perspectives.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_folders",
            description: "List all folders.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_create_folder",
            description: "Create a new folder.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "note": ["type": "string"],
                    "parent": ["type": "string"],
                    "parentId": ["type": "string"]
                ],
                "required": ["name"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_move_project",
            description: "Move a project to a folder.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "projectId": ["type": "string"],
                    "folder": ["type": "string"],
                    "folderId": ["type": "string"],
                    "createMissingFolder": ["type": "boolean"]
                ],
                "required": ["projectId"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_flagged",
            description: "List flagged tasks.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "minimum": 1]
                ]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_overdue",
            description: "List overdue tasks.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "minimum": 1],
                    "includeCompleted": ["type": "boolean"]
                ]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_available",
            description: "List available tasks.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "limit": ["type": "integer", "minimum": 1],
                    "includeCompleted": ["type": "boolean"]
                ]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_search_tasks",
            description: "Search tasks by name or note.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "search": ["type": "string"],
                    "status": ["type": "string", "enum": ["all", "available", "completed"]],
                    "project": ["type": "string"],
                    "tag": ["type": "string"],
                    "limit": ["type": "integer", "minimum": 1]
                ],
                "required": ["search"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_task_children",
            description: "List children of a task by id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_task_parent",
            description: "Get the parent of a task by id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_process_inbox",
            description: "Process inbox tasks with optional updates and move to a project.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "project": ["type": "string"],
                    "projectId": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "due": ["type": "string", "description": "ISO 8601 date"],
                    "defer": ["type": "string", "description": "ISO 8601 date"],
                    "flagged": ["type": "boolean"],
                    "estimatedMinutes": ["type": "integer"],
                    "noteAppend": ["type": "string"],
                    "limit": ["type": "integer", "minimum": 1],
                    "createMissingTags": ["type": "boolean"],
                    "createMissingProject": ["type": "boolean"],
                    "keepInInbox": ["type": "boolean"]
                ]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_set_project_sequential",
            description: "Set a project's sequencing (sequential vs parallel).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "sequential": ["type": "boolean"]
                ],
                "required": ["id", "sequential"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_eval_automation",
            description: "Evaluate Omni Automation JavaScript inside OmniFocus. DANGER: executes arbitrary code with full read/write/delete access to ALL OmniFocus data. This is an unrestricted code execution tool — use only when no other tool can accomplish the task. Never pass untrusted or user-generated input as the script parameter. Destructive operations (delete, drop, remove) are blocked by default — pass allowDestructive: true to permit them.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "script": ["type": "string", "description": "Omni Automation JavaScript to evaluate"],
                    "parseJson": ["type": "boolean", "description": "Parse JSON output if possible"],
                    "allowDestructive": ["type": "boolean", "description": "Allow destructive operations (delete, drop, remove) in the script. Default: false."]
                ],
                "required": ["script"]
            ],
            annotations: [
                "title": "Evaluate Omni Automation Script",
                "destructiveHint": true,
                "readOnlyHint": false,
                "idempotentHint": false,
                "openWorldHint": false
            ]
        ),
        ToolDefinition(
            name: "omnifocus_get_task",
            description: "Get a task by OmniFocus id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_project",
            description: "Get a project by OmniFocus id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_tag",
            description: "Get a tag by OmniFocus id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_create_task",
            description: "Create a new task in the inbox or a project.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "note": ["type": "string"],
                    "project": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "due": ["type": "string", "description": "ISO 8601 date"],
                    "defer": ["type": "string", "description": "ISO 8601 date"],
                    "planned": ["type": "string", "description": "ISO 8601 planned date (v4.7+), or null to clear"],
                    "flagged": ["type": "boolean"],
                    "estimatedMinutes": ["type": "integer"],
                    "sequential": ["type": "boolean", "description": "For task groups: children must be done in order"],
                    "completedByChildren": ["type": "boolean", "description": "Auto-complete when all children done"],
                    "shouldUseFloatingTimeZone": ["type": "boolean", "description": "Use floating time zone for dates"],
                    "inbox": ["type": "boolean"],
                    "createMissingTags": ["type": "boolean"],
                    "createMissingProject": ["type": "boolean"]
                ],
                "required": ["name"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_create_project",
            description: "Create a new project.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "note": ["type": "string"],
                    "due": ["type": "string", "description": "ISO 8601 date"],
                    "defer": ["type": "string", "description": "ISO 8601 date"],
                    "flagged": ["type": "boolean"],
                    "estimatedMinutes": ["type": "integer"],
                    "sequential": ["type": "boolean", "description": "Tasks must be completed in order"],
                    "containsSingletonActions": ["type": "boolean", "description": "Single-action list (no next action)"],
                    "reviewInterval": ["type": "object", "properties": ["steps": ["type": "integer"], "unit": ["type": "string", "enum": ["days", "weeks", "months", "years"]]], "description": "Review interval"],
                    "shouldUseFloatingTimeZone": ["type": "boolean", "description": "Use floating time zone for dates"]
                ],
                "required": ["name"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_create_tag",
            description: "Create a new tag.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "name": ["type": "string"],
                    "active": ["type": "boolean"]
                ],
                "required": ["name"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_update_task",
            description: "Update an existing task by id.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "name": ["type": "string"],
                    "note": ["type": "string"],
                    "project": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "due": ["type": "string", "description": "ISO 8601 date"],
                    "defer": ["type": "string", "description": "ISO 8601 date"],
                    "planned": ["type": "string", "description": "ISO 8601 planned date (v4.7+), or null to clear"],
                    "flagged": ["type": "boolean"],
                    "estimatedMinutes": ["type": "integer"],
                    "sequential": ["type": "boolean", "description": "For task groups: children must be done in order"],
                    "completedByChildren": ["type": "boolean", "description": "Auto-complete when all children done"],
                    "shouldUseFloatingTimeZone": ["type": "boolean", "description": "Use floating time zone for dates"],
                    "createMissingTags": ["type": "boolean"],
                    "createMissingProject": ["type": "boolean"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_update_project",
            description: "Update an existing project by id.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "name": ["type": "string"],
                    "note": ["type": "string"],
                    "due": ["type": "string", "description": "ISO 8601 date"],
                    "defer": ["type": "string", "description": "ISO 8601 date"],
                    "flagged": ["type": "boolean"],
                    "estimatedMinutes": ["type": "integer"],
                    "sequential": ["type": "boolean", "description": "Tasks must be completed in order"],
                    "containsSingletonActions": ["type": "boolean", "description": "Single-action list"],
                    "reviewInterval": ["type": "object", "properties": ["steps": ["type": "integer"], "unit": ["type": "string", "enum": ["days", "weeks", "months", "years"]]], "description": "Review interval"],
                    "shouldUseFloatingTimeZone": ["type": "boolean", "description": "Use floating time zone for dates"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_update_tag",
            description: "Update an existing tag by id.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "name": ["type": "string"],
                    "active": ["type": "boolean"],
                    "allowsNextAction": ["type": "boolean", "description": "Whether tasks with this tag are considered for next action"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_complete_task",
            description: "Mark a task complete by id.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "completionDate": ["type": "string", "description": "ISO 8601 date"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_complete_project",
            description: "Mark a project complete by id.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "completionDate": ["type": "string", "description": "ISO 8601 date"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_delete_task",
            description: "Delete a task by id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: destructiveAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_delete_project",
            description: "Delete a project by id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: destructiveAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_delete_tag",
            description: "Delete a tag by id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: destructiveAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_uncomplete_task",
            description: "Mark a task incomplete (undo completion) by id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_uncomplete_project",
            description: "Mark a project active again (undo completion) by id.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_append_to_note",
            description: "Append text to the note of a task or project.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "type": ["type": "string", "enum": ["task", "project"]],
                    "text": ["type": "string"]
                ],
                "required": ["id", "text"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_search_tags",
            description: "Search tags by name (case-insensitive substring).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Substring to match against tag names"]
                ],
                "required": ["query"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_set_project_status",
            description: "Set a project's status to active, on_hold, or dropped.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "status": ["type": "string", "enum": ["active", "on_hold", "dropped"]]
                ],
                "required": ["id", "status"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_folder",
            description: "Get a folder by id or name, including its projects and subfolders.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "name": ["type": "string"]
                ]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_update_folder",
            description: "Update a folder's name by id.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "name": ["type": "string"]
                ],
                "required": ["id", "name"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_delete_folder",
            description: "Delete a folder by id. WARNING: irreversibly deletes the folder and ALL contained projects and their tasks.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: destructiveAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_task_counts",
            description: "Get aggregate task counts: total, available, completed, overdue, flagged, inbox.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_project_counts",
            description: "Get aggregate project counts: total, active, on_hold, dropped, stalled.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_forecast",
            description: "Get forecast view: overdue, today, flagged, and due this week task lists.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_create_subtask",
            description: "Create a subtask under an existing task.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "parentId": ["type": "string"],
                    "name": ["type": "string"],
                    "note": ["type": "string"],
                    "tags": ["type": "array", "items": ["type": "string"]],
                    "due": ["type": "string", "description": "ISO 8601 date"],
                    "defer": ["type": "string", "description": "ISO 8601 date"],
                    "planned": ["type": "string", "description": "ISO 8601 planned date (v4.7+)"],
                    "flagged": ["type": "boolean"],
                    "estimatedMinutes": ["type": "integer"],
                    "sequential": ["type": "boolean"],
                    "completedByChildren": ["type": "boolean"],
                    "createMissingTags": ["type": "boolean"]
                ],
                "required": ["parentId", "name"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_duplicate_task",
            description: "Duplicate a task, optionally with a new name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "name": ["type": "string", "description": "Optional new name for the duplicate"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_create_tasks_batch",
            description: "Create multiple tasks in one call.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "tasks": [
                        "type": "array",
                        "items": [
                            "type": "object",
                            "properties": [
                                "name": ["type": "string"],
                                "project": ["type": "string"],
                                "note": ["type": "string"],
                                "tags": ["type": "array", "items": ["type": "string"]],
                                "due": ["type": "string"],
                                "defer": ["type": "string"],
                                "flagged": ["type": "boolean"],
                                "estimatedMinutes": ["type": "integer"]
                            ],
                            "required": ["name"]
                        ]
                    ]
                ],
                "required": ["tasks"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_delete_tasks_batch",
            description: "Delete multiple tasks by id in one call.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"]]
                ],
                "required": ["ids"]
            ],
            annotations: destructiveAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_move_tasks_batch",
            description: "Move multiple tasks to a project in one call.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"]],
                    "project": ["type": "string", "description": "Project name to move tasks to"]
                ],
                "required": ["ids", "project"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_notifications",
            description: "List alarms/notifications on a task.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_add_notification",
            description: "Add an absolute-date alarm/notification to a task.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "date": ["type": "string", "description": "ISO 8601 date for the alarm"]
                ],
                "required": ["id", "date"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_remove_notification",
            description: "Remove an alarm/notification from a task.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Task id"],
                    "notificationId": ["type": "string", "description": "Notification id to remove"]
                ],
                "required": ["id", "notificationId"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_set_task_repetition",
            description: "Set or clear the repetition rule on a task using iCal RRULE format.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "rule": ["type": "string", "description": "iCal RRULE string, e.g. FREQ=WEEKLY;INTERVAL=1, or null to clear"],
                    "scheduleType": ["type": "string", "enum": ["due", "defer", "fixed"], "description": "How the repetition is scheduled"],
                    "anchorDateKey": ["type": "string", "enum": ["due", "defer", "planned"], "description": "v4.7+: which date anchors repetition"],
                    "catchUpAutomatically": ["type": "boolean", "description": "Whether missed repetitions should catch up"]
                ],
                "required": ["id", "rule"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_mark_reviewed",
            description: "Mark a project as reviewed (updates lastReviewDate to now).",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_drop_task",
            description: "Drop a task (mark as dropped without deleting). Preserves the task unlike delete.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_import_taskpaper",
            description: "Import tasks from TaskPaper-formatted text into the inbox or a project.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "text": ["type": "string", "description": "TaskPaper-formatted text to import"],
                    "project": ["type": "string", "description": "Optional project name to import into"]
                ],
                "required": ["text"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_add_relative_notification",
            description: "Add a relative-time notification to a task (fires N seconds before due date).",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Task id"],
                    "beforeSeconds": ["type": "number", "description": "Seconds before due date to fire (e.g. 3600 = 1 hour before)"]
                ],
                "required": ["id", "beforeSeconds"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_move_tag",
            description: "Move a tag under a different parent tag, or to the root level.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Tag id to move"],
                    "parentTag": ["type": "string", "description": "Parent tag name, or omit/null for root"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_move_folder",
            description: "Move a folder under a different parent folder, or to the root level.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Folder id to move"],
                    "parentFolder": ["type": "string", "description": "Parent folder name, or omit/null for root"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_convert_task_to_project",
            description: "Convert a task (and its children) into a project.",
            inputSchema: [
                "type": "object",
                "properties": ["id": ["type": "string"]],
                "required": ["id"]
            ],
            annotations: destructiveAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_duplicate_project",
            description: "Duplicate a project, optionally with a new name.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string"],
                    "name": ["type": "string", "description": "Optional new name for the duplicate"]
                ],
                "required": ["id"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_forecast_tag",
            description: "Get the forecast tag (OmniAutomation only, v4.5+). Returns null in JXA.",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_clean_up",
            description: "Run OmniFocus clean-up (compact database / hide completed items).",
            inputSchema: ["type": "object", "properties": [String: Any]()],
            annotations: destructiveAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_settings",
            description: "Retrieve OmniFocus application settings. Pass specific keys to read their values.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "keys": ["type": "array", "items": ["type": "string"], "description": "Setting keys to retrieve"]
                ]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_list_linked_files",
            description: "List linked file URLs attached to a task.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Task id"]
                ],
                "required": ["id"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_add_linked_file",
            description: "Add a linked file URL to a task.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Task id"],
                    "url": ["type": "string", "description": "File URL to link"]
                ],
                "required": ["id", "url"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_remove_linked_file",
            description: "Remove a linked file URL from a task.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Task id"],
                    "url": ["type": "string", "description": "File URL to remove"]
                ],
                "required": ["id", "url"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_search_projects",
            description: "Search projects by name using native database search when available.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query"]
                ],
                "required": ["query"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_search_folders",
            description: "Search folders by name using native database search when available.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query"]
                ],
                "required": ["query"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_search_tasks_native",
            description: "Search tasks using native database search (database.tasksMatching) when available, with manual fallback.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "query": ["type": "string", "description": "Search query"]
                ],
                "required": ["query"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_lookup_url",
            description: "Look up an OmniFocus object by its URL (omnifocus:///task/ID, etc). Returns the serialized object.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "url": ["type": "string", "description": "OmniFocus URL to look up"]
                ],
                "required": ["url"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_forecast_days",
            description: "Get forecast day objects for upcoming days, including badge counts and deferred counts.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "count": ["type": "integer", "description": "Number of days to retrieve (default 14)"]
                ]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_get_focus",
            description: "Get currently focused projects and folders.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_set_focus",
            description: "Set focus to specific projects/folders, or pass empty ids array to unfocus.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"], "description": "Array of project/folder ids to focus, or empty to unfocus"]
                ],
                "required": ["ids"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_undo",
            description: "Undo the last action in OmniFocus.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_redo",
            description: "Redo the last undone action in OmniFocus.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_save",
            description: "Save the OmniFocus database.",
            inputSchema: [
                "type": "object",
                "properties": [:]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_duplicate_tasks_batch",
            description: "Duplicate multiple tasks by their ids.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"], "description": "Task ids to duplicate"]
                ],
                "required": ["ids"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_duplicate_tags",
            description: "Duplicate multiple tags by their ids.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"], "description": "Tag ids to duplicate"]
                ],
                "required": ["ids"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_move_projects_batch",
            description: "Move multiple projects to a target folder.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"], "description": "Project ids to move"],
                    "folder": ["type": "string", "description": "Target folder name"]
                ],
                "required": ["ids"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_reorder_task_tags",
            description: "Reorder tags on a task by removing all and re-adding in specified order.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Task id"],
                    "tagIds": ["type": "array", "items": ["type": "string"], "description": "Ordered array of tag ids"]
                ],
                "required": ["id", "tagIds"]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_copy_tasks",
            description: "Copy tasks to the system pasteboard.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "ids": ["type": "array", "items": ["type": "string"], "description": "Task ids to copy"]
                ],
                "required": ["ids"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_paste_tasks",
            description: "Paste tasks from the system pasteboard into a project.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "Target project name (optional, pastes to inbox if omitted)"]
                ]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_next_repetition_date",
            description: "Compute the next repetition date for a repeating task.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Task id"],
                    "afterDate": ["type": "string", "description": "ISO 8601 date to compute next occurrence after (default: now)"]
                ],
                "required": ["id"]
            ],
            annotations: readOnlyAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_set_forecast_tag",
            description: "Set or clear the forecast tag. Pass a tag id to set, or null/empty to clear.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Tag id to set as forecast tag, or null to clear"]
                ]
            ],
            annotations: mutatingAnnotation
        ),
        ToolDefinition(
            name: "omnifocus_set_notification_repeat",
            description: "Set the repeat interval on an existing notification/alarm.",
            inputSchema: [
                "type": "object",
                "properties": [
                    "id": ["type": "string", "description": "Task id"],
                    "notificationId": ["type": "string", "description": "Notification id"],
                    "repeatInterval": ["type": "number", "description": "Repeat interval in seconds (0 to disable)"]
                ],
                "required": ["id", "notificationId", "repeatInterval"]
            ],
            annotations: mutatingAnnotation
        )
    ]
    private let stdout = FileHandle.standardOutput
    private let stdin = FileHandle.standardInput
    private var automationBackendAvailable: Bool?
    private var automationBackendProbeTime: Date?

    private let maxBufferSize = 10 * 1024 * 1024 // 10 MB

    func run() {
        var buffer = Data()
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty {
                break
            }
            buffer.append(chunk)
            if buffer.count > maxBufferSize {
                sendError(id: nil, code: -32600, message: "Request too large", data: "Input exceeds \(maxBufferSize) byte limit")
                buffer.removeAll()
                continue
            }
            while let range = buffer.range(of: Data([0x0A])) {
                let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                handleLine(lineData)
            }
        }
        if !buffer.isEmpty {
            handleLine(buffer)
        }
    }

    private func handleLine(_ data: Data) {
        guard let line = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !line.isEmpty else {
            return
        }
        let jsonObject: Any
        do {
            jsonObject = try JSONSerialization.jsonObject(with: Data(line.utf8), options: [])
        } catch {
            sendError(id: nil, code: -32700, message: "Parse error", data: error.localizedDescription)
            return
        }
        guard let message = jsonObject as? [String: Any] else {
            sendError(id: nil, code: -32600, message: "Invalid Request", data: "Message is not an object")
            return
        }
        do {
            try handleMessage(message)
        } catch let error as MCPError {
            let code: Int
            switch error {
            case .methodNotFound:
                code = -32601
            case .invalidParams, .toolNotFound:
                code = -32602
            case .invalidRequest:
                code = -32600
            case .toolError, .scriptError:
                code = -32000
            }
            sendError(id: message["id"], code: code, message: error.description)
        } catch {
            sendError(id: message["id"], code: -32603, message: "Internal error", data: error.localizedDescription)
        }
    }

    private func handleMessage(_ message: [String: Any]) throws {
        let id = message["id"]
        let method = message["method"] as? String

        if method == nil {
            throw MCPError.invalidRequest("Missing method")
        }

        switch method {
        case "initialize":
            let result: [String: Any] = [
                "protocolVersion": "2024-11-05",
                "capabilities": ["tools": [String: Any]()],
                "serverInfo": ["name": "omnifocus-mcp", "version": "0.2.0"]
            ]
            sendResult(id: id, result: result)
        case "tools/list":
            let toolEntries = tools.map { tool -> [String: Any] in
                var entry: [String: Any] = [
                    "name": tool.name,
                    "description": tool.description,
                    "inputSchema": tool.inputSchema
                ]
                if let annotations = tool.annotations {
                    entry["annotations"] = annotations
                }
                return entry
            }
            sendResult(id: id, result: ["tools": toolEntries])
        case "tools/call":
            guard let params = message["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                throw MCPError.invalidParams("Missing tool name")
            }
            let arguments = params["arguments"] as? [String: Any] ?? [String: Any]()
            let resultValue = try callTool(named: toolName, arguments: arguments)
            let jsonText: String
            if let str = resultValue as? String {
                jsonText = str
            } else if JSONSerialization.isValidJSONObject(resultValue),
                      let jsonData = try? JSONSerialization.data(withJSONObject: resultValue, options: [.sortedKeys]),
                      let encoded = String(data: jsonData, encoding: .utf8) {
                jsonText = encoded
            } else {
                jsonText = "{}"
            }
            let response: [String: Any] = [
                "content": [["type": "text", "text": jsonText]]
            ]
            sendResult(id: id, result: response)
        case "initialized", "shutdown", "exit":
            return
        default:
            throw MCPError.methodNotFound("Unknown method: \(method ?? "")")
        }
    }

    private func callTool(named name: String, arguments: [String: Any]) throws -> Any {
        switch name {
        case "omnifocus_list_tasks":
            return try callAction("list_tasks", params: arguments)
        case "omnifocus_list_inbox":
            return try callAction("list_inbox", params: arguments)
        case "omnifocus_list_projects":
            return try callAction("list_projects", params: arguments)
        case "omnifocus_list_tags":
            return try callAction("list_tags", params: arguments)
        case "omnifocus_list_perspectives":
            return try callAction("list_perspectives", params: arguments)
        case "omnifocus_list_folders":
            return try callAction("list_folders", params: arguments)
        case "omnifocus_create_folder":
            return try callAction("create_folder", params: arguments)
        case "omnifocus_move_project":
            return try callAction("move_project", params: arguments)
        case "omnifocus_list_flagged":
            return try callAction("list_flagged", params: arguments)
        case "omnifocus_list_overdue":
            return try callAction("list_overdue", params: arguments)
        case "omnifocus_list_available":
            return try callAction("list_available", params: arguments)
        case "omnifocus_search_tasks":
            return try callAction("search_tasks", params: arguments)
        case "omnifocus_list_task_children":
            return try callAction("list_task_children", params: arguments)
        case "omnifocus_get_task_parent":
            return try callAction("get_task_parent", params: arguments)
        case "omnifocus_process_inbox":
            return try callAction("process_inbox", params: arguments)
        case "omnifocus_set_project_sequential":
            return try callAction("set_project_sequential", params: arguments)
        case "omnifocus_eval_automation":
            guard let script = arguments["script"] as? String else {
                throw MCPError.invalidParams("Missing script")
            }
            let allowDestructive = arguments["allowDestructive"] as? Bool ?? false
            if !allowDestructive {
                let destructiveKeywords = [
                    "delete", "remove", "drop", "markComplete", "markIncomplete",
                    "cleanUp"
                ]
                // Match both dot-notation (.delete() ) and bracket-notation (['delete'](), ["delete"]())
                let dotPatterns = destructiveKeywords.map { "\\.\($0)\\s*\\(" }
                let bracketPatterns = destructiveKeywords.map { "\\[['\"]\\s*\($0)\\s*['\"]\\]\\s*\\(" }
                let namedFunctionPatterns = [
                    "\\bdeleteObject\\s*\\(",
                    "\\bconvertTasksToProjects\\s*\\(", "\\bmoveSections\\s*\\(",
                    "\\bmoveTags\\s*\\(", "\\bduplicateSections\\s*\\(",
                    "Task\\.byParsingTransportText\\s*\\(",
                    "\\bcopyTasksToPasteboard\\s*\\(", "\\bpasteTasksFromPasteboard\\s*\\("
                ]
                let destructivePatterns = dotPatterns + bracketPatterns + namedFunctionPatterns
                let combined = destructivePatterns.joined(separator: "|")
                if let regex = try? NSRegularExpression(pattern: combined, options: []),
                   regex.firstMatch(in: script, options: [], range: NSRange(script.startIndex..., in: script)) != nil {
                    throw MCPError.invalidParams(
                        "Script contains destructive operations. Use the dedicated MCP tools for delete/drop/move/complete operations, or pass allowDestructive: true to override this safety check."
                    )
                }
            }
            let parseJson = arguments["parseJson"] as? Bool ?? true
            return try runOmniAutomationScript(script, parseJson: parseJson)
        case "omnifocus_get_task":
            return try callAction("get_task", params: arguments)
        case "omnifocus_get_project":
            return try callAction("get_project", params: arguments)
        case "omnifocus_get_tag":
            return try callAction("get_tag", params: arguments)
        case "omnifocus_create_task":
            return try callAction("create_task", params: arguments)
        case "omnifocus_create_project":
            return try callAction("create_project", params: arguments)
        case "omnifocus_create_tag":
            return try callAction("create_tag", params: arguments)
        case "omnifocus_update_task":
            return try callAction("update_task", params: arguments)
        case "omnifocus_update_project":
            return try callAction("update_project", params: arguments)
        case "omnifocus_update_tag":
            return try callAction("update_tag", params: arguments)
        case "omnifocus_complete_task":
            return try callAction("complete_task", params: arguments)
        case "omnifocus_complete_project":
            return try callAction("complete_project", params: arguments)
        case "omnifocus_delete_task":
            return try callAction("delete_task", params: arguments)
        case "omnifocus_delete_project":
            return try callAction("delete_project", params: arguments)
        case "omnifocus_delete_tag":
            return try callAction("delete_tag", params: arguments)
        case "omnifocus_uncomplete_task":
            return try callAction("uncomplete_task", params: arguments)
        case "omnifocus_uncomplete_project":
            return try callAction("uncomplete_project", params: arguments)
        case "omnifocus_append_to_note":
            return try callAction("append_to_note", params: arguments)
        case "omnifocus_search_tags":
            return try callAction("search_tags", params: arguments)
        case "omnifocus_set_project_status":
            return try callAction("set_project_status", params: arguments)
        case "omnifocus_get_folder":
            return try callAction("get_folder", params: arguments)
        case "omnifocus_update_folder":
            return try callAction("update_folder", params: arguments)
        case "omnifocus_delete_folder":
            return try callAction("delete_folder", params: arguments)
        case "omnifocus_get_task_counts":
            return try callAction("get_task_counts", params: arguments)
        case "omnifocus_get_project_counts":
            return try callAction("get_project_counts", params: arguments)
        case "omnifocus_get_forecast":
            return try callAction("get_forecast", params: arguments)
        case "omnifocus_create_subtask":
            return try callAction("create_subtask", params: arguments)
        case "omnifocus_duplicate_task":
            return try callAction("duplicate_task", params: arguments)
        case "omnifocus_create_tasks_batch":
            return try callAction("create_tasks_batch", params: arguments)
        case "omnifocus_delete_tasks_batch":
            return try callAction("delete_tasks_batch", params: arguments)
        case "omnifocus_move_tasks_batch":
            return try callAction("move_tasks_batch", params: arguments)
        case "omnifocus_list_notifications":
            return try callAction("list_notifications", params: arguments)
        case "omnifocus_add_notification":
            return try callAction("add_notification", params: arguments)
        case "omnifocus_remove_notification":
            return try callAction("remove_notification", params: arguments)
        case "omnifocus_set_task_repetition":
            return try callAction("set_task_repetition", params: arguments)
        case "omnifocus_mark_reviewed":
            return try callAction("mark_reviewed", params: arguments)
        case "omnifocus_drop_task":
            return try callAction("drop_task", params: arguments)
        case "omnifocus_import_taskpaper":
            return try callAction("import_taskpaper", params: arguments)
        case "omnifocus_add_relative_notification":
            return try callAction("add_relative_notification", params: arguments)
        case "omnifocus_move_tag":
            return try callAction("move_tag", params: arguments)
        case "omnifocus_move_folder":
            return try callAction("move_folder", params: arguments)
        case "omnifocus_convert_task_to_project":
            return try callAction("convert_to_project", params: arguments)
        case "omnifocus_duplicate_project":
            return try callAction("duplicate_project", params: arguments)
        case "omnifocus_get_forecast_tag":
            return try callAction("get_forecast_tag", params: arguments)
        case "omnifocus_clean_up":
            return try callAction("clean_up", params: arguments)
        case "omnifocus_get_settings":
            return try callAction("get_settings", params: arguments)
        case "omnifocus_list_linked_files":
            return try callAction("list_linked_files", params: arguments)
        case "omnifocus_add_linked_file":
            return try callAction("add_linked_file", params: arguments)
        case "omnifocus_remove_linked_file":
            return try callAction("remove_linked_file", params: arguments)
        case "omnifocus_search_projects":
            return try callAction("search_projects", params: arguments)
        case "omnifocus_search_folders":
            return try callAction("search_folders", params: arguments)
        case "omnifocus_search_tasks_native":
            return try callAction("search_tasks_native", params: arguments)
        case "omnifocus_lookup_url":
            return try callAction("lookup_url", params: arguments)
        case "omnifocus_get_forecast_days":
            return try callAction("get_forecast_days", params: arguments)
        case "omnifocus_get_focus":
            return try callAction("get_focus", params: arguments)
        case "omnifocus_set_focus":
            return try callAction("set_focus", params: arguments)
        case "omnifocus_undo":
            return try callAction("undo", params: arguments)
        case "omnifocus_redo":
            return try callAction("redo", params: arguments)
        case "omnifocus_save":
            return try callAction("save", params: arguments)
        case "omnifocus_duplicate_tasks_batch":
            return try callAction("duplicate_tasks_batch", params: arguments)
        case "omnifocus_duplicate_tags":
            return try callAction("duplicate_tags", params: arguments)
        case "omnifocus_move_projects_batch":
            return try callAction("move_projects_batch", params: arguments)
        case "omnifocus_reorder_task_tags":
            return try callAction("reorder_task_tags", params: arguments)
        case "omnifocus_copy_tasks":
            return try callAction("copy_tasks", params: arguments)
        case "omnifocus_paste_tasks":
            return try callAction("paste_tasks", params: arguments)
        case "omnifocus_next_repetition_date":
            return try callAction("next_repetition_date", params: arguments)
        case "omnifocus_set_forecast_tag":
            return try callAction("set_forecast_tag", params: arguments)
        case "omnifocus_set_notification_repeat":
            return try callAction("set_notification_repeat", params: arguments)
        default:
            throw MCPError.toolNotFound(name)
        }
    }

    private func callAction(_ action: String, params: [String: Any]) throws -> Any {
        let payload: [String: Any] = ["action": action, "params": params]
        let backend = preferredBackend()
        switch backend {
        case .automation:
            let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
            guard let jsonString = String(data: jsonData, encoding: .utf8) else {
                throw MCPError.scriptError("Unable to encode input JSON")
            }
            let script = omniAutomationScript.replacingOccurrences(of: "__OF_INPUT_JSON__", with: javaScriptStringLiteral(jsonString))
            return try runOmniAutomationScript(script, parseJson: true)
        case .jxa:
            return try runJXAScript(payload)
        }
    }

    private func runJXAScript(_ payload: [String: Any]) throws -> Any {
        let jsonData = try JSONSerialization.data(withJSONObject: payload, options: [])
        guard let jsonString = String(data: jsonData, encoding: .utf8) else {
            throw MCPError.scriptError("Unable to encode input JSON")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-l", "JavaScript", "-e", jxaScript]

        var environment = ProcessInfo.processInfo.environment
        environment["OF_INPUT_JSON"] = jsonString
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        var timedOut = false
        let timeoutItem = DispatchWorkItem { timedOut = true; process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)
        process.waitUntilExit()
        timeoutItem.cancel()

        if timedOut {
            throw MCPError.scriptError("OmniFocus script timed out after 30 seconds")
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""
        let outputText = String(data: outputData, encoding: .utf8) ?? ""
        let trimmedOutput = outputText.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedError = errorText.trimmingCharacters(in: .whitespacesAndNewlines)

        if process.terminationStatus != 0 {
            if let parsed = parseJsonIfPossible(trimmedOutput) ?? parseJsonIfPossible(trimmedError) {
                return parsed
            }
            throw MCPError.scriptError(trimmedError.isEmpty ? "OmniFocus script failed" : trimmedError)
        }

        if let parsed = parseJsonIfPossible(trimmedOutput) {
            return parsed
        }
        if trimmedOutput.isEmpty, let parsed = parseJsonIfPossible(trimmedError) {
            return parsed
        }
        if trimmedOutput.isEmpty {
            throw MCPError.scriptError(trimmedError.isEmpty ? "Empty response from OmniFocus" : trimmedError)
        }
        throw MCPError.scriptError("Unable to parse OmniFocus response")
    }

    private func runOmniAutomationScript(_ script: String, parseJson: Bool) throws -> Any {
        let rawAppPath = ProcessInfo.processInfo.environment["OF_APP_PATH"] ?? "/Applications/OmniFocus.app"
        // Validate path: only allow characters safe for embedding in AppleScript string literals
        let allowedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "/._- "))
        guard rawAppPath.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            throw MCPError.scriptError("OF_APP_PATH contains unsafe characters: \(rawAppPath)")
        }
        let appPath = rawAppPath
        let termsPath = appPath.replacingOccurrences(of: "\"", with: "\\\"")
        let appleScriptLines = [
            "using terms from application \"\(termsPath)\"",
            "on run argv",
            "set appPath to item 1 of argv",
            "set js to item 2 of argv",
            "tell application appPath",
            "try",
            "tell default document",
            "set resultValue to evaluate javascript js",
            "end tell",
            "on error",
            "set resultValue to evaluate javascript js",
            "end try",
            "end tell",
            "return resultValue",
            "end run",
            "end using terms from"
        ]

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = appleScriptLines.flatMap { ["-e", $0] } + [appPath, script]

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        try process.run()
        var timedOut = false
        let timeoutItem = DispatchWorkItem { timedOut = true; process.terminate() }
        DispatchQueue.global().asyncAfter(deadline: .now() + 30, execute: timeoutItem)
        process.waitUntilExit()
        timeoutItem.cancel()

        if timedOut {
            throw MCPError.scriptError("OmniFocus script timed out after 30 seconds")
        }

        let outputData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = stderrPipe.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(data: errorData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw MCPError.scriptError(errorText.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let outputText = String(data: outputData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if outputText.isEmpty {
            let trimmedError = errorText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedError.isEmpty {
                throw MCPError.scriptError(trimmedError)
            }
            return ""
        }

        if parseJson, let data = outputText.data(using: .utf8) {
            if let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) {
                return json
            }
        }

        return outputText
    }

    private func javaScriptStringLiteral(_ value: String) -> String {
        var result = "'"
        for unit in value.utf16 {
            switch unit {
            case 0x27:
                result += "\\'"
            case 0x5C:
                result += "\\\\"
            case 0x0A:
                result += "\\n"
            case 0x0D:
                result += "\\r"
            case 0x09:
                result += "\\t"
            default:
                if unit < 0x20 || unit > 0x7E {
                    result += String(format: "\\u%04X", unit)
                } else if let scalar = UnicodeScalar(unit) {
                    result.append(Character(scalar))
                }
            }
        }
        result += "'"
        return result
    }

    private func parseJsonIfPossible(_ text: String) -> Any? {
        guard !text.isEmpty, let data = text.data(using: .utf8) else {
            return nil
        }
        return try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    private enum BackendChoice {
        case automation
        case jxa
    }

    private func preferredBackend() -> BackendChoice {
        if let forced = ProcessInfo.processInfo.environment["OF_BACKEND"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            if forced == "jxa" || forced == "applescript" {
                return .jxa
            }
            if forced == "automation" || forced == "omnijs" || forced == "omni-automation" {
                return .automation
            }
        }
        if isAutomationBackendAvailable() {
            return .automation
        }
        return .jxa
    }

    private func isAutomationBackendAvailable() -> Bool {
        // Re-probe every 5 minutes in case OmniFocus was restarted
        if let cached = automationBackendAvailable,
           let probeTime = automationBackendProbeTime,
           Date().timeIntervalSince(probeTime) < 300 {
            return cached
        }
        let probe = "JSON.stringify({hasDatabase: (typeof database !== 'undefined') || (typeof document !== 'undefined' && document && typeof document.database !== 'undefined') || (typeof flattenedProjects !== 'undefined') || (typeof moveSections !== 'undefined')})"
        if let result = try? runOmniAutomationScript(probe, parseJson: true),
           let dict = result as? [String: Any],
           let hasDatabase = dict["hasDatabase"] as? Bool {
            automationBackendAvailable = hasDatabase
            automationBackendProbeTime = Date()
            return hasDatabase
        }
        automationBackendAvailable = false
        automationBackendProbeTime = Date()
        return false
    }

    private func sendResult(id: Any?, result: [String: Any]) {
        guard let responseId = id else {
            return
        }
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": responseId,
            "result": result
        ]
        send(response)
    }

    private func sendError(id: Any?, code: Int, message: String, data: Any? = nil) {
        var errorObject: [String: Any] = ["code": code, "message": message]
        if let data = data { errorObject["data"] = data }
        let response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id ?? NSNull(),
            "error": errorObject
        ]
        send(response)
    }

    private func send(_ payload: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return
        }
        stdout.write(data)
        stdout.write(Data([0x0A]))
    }
}
