ObjC.import('Foundation');

function env(name) {
  var value = $.NSProcessInfo.processInfo.environment.objectForKey(name);
  if (!value) {
    return null;
  }
  return ObjC.unwrap(value);
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

// === Shared Utilities (from JSShared.swift, inlined here for single-string execution) ===

// __SHARED_JS__

// === End Shared Utilities ===




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
    repetitionEndDate: toISO(firstValue(task, ['repetitionEndDate'])),
    maxRepetitions: safeCall(task, 'maxRepetitions'),
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
    plannedDate: toISO(firstValue(project, ['plannedDate'])),
    effectivePlannedDate: toISO(firstValue(project, ['effectivePlannedDate'])),
    flagged: safeCall(project, 'flagged'),
    sequential: safeCall(project, 'parallel') !== null ? !safeCall(project, 'parallel') : null,
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
    // Verify: mutually exclusive tags may have been silently dropped (4.8.9+)
    var actualTags = [];
    try { actualTags = arrayify(task.tags()); } catch (e) { try { actualTags = arrayify(task.tags); } catch (e2) {} }
    if (actualTags.length < tagObjects.length) {
      return ['Some tags were not applied (mutually exclusive tags may have been rejected). Requested: ' + tagObjects.length + ', applied: ' + actualTags.length];
    }
  }
  return [];
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
  var properties = { name: params.name };
  var task = null;
  if (project) {
    task = project.make({new: 'task', withProperties: properties});
  } else {
    task = doc.make({new: 'inbox task', withProperties: properties});
  }
  var warnings = applyCommonTaskFields(task, params, doc);
  var result = taskToJSON(task);
  if (warnings.length > 0) { result.warnings = warnings; }
  return result;
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
  if (params.childrenAreMutuallyExclusive !== undefined) {
    safeSet(tag, 'childrenAreMutuallyExclusive', params.childrenAreMutuallyExclusive);
  }
  return tagToJSON(tag);
}

function updateTask(params) {
  var doc = getDocument();
  var task = findTaskById(doc, params.id);
  if (!task) {
    throw new Error('Task not found');
  }
  var warnings = applyCommonTaskFields(task, params, doc);
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
  var result = taskToJSON(task);
  if (warnings.length > 0) { result.warnings = warnings; }
  return result;
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
  if (params.planned !== undefined) {
    var pd = parseDate(params.planned);
    if (pd) { safeSet(project, 'plannedDate', pd); }
    if (params.planned === null) { safeSet(project, 'plannedDate', null); }
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
  if (params.childrenAreMutuallyExclusive !== undefined) {
    safeSet(tag, 'childrenAreMutuallyExclusive', params.childrenAreMutuallyExclusive);
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
  var plannedToday = [], plannedSoon = [], forecastTagged = [];
  // JXA does not support Tag.forecastTag, so forecastTagged stays empty
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
    var plannedDate = dateValue(firstValue(task, ['plannedDate']));
    if (plannedDate) {
      if (plannedDate.getTime() <= todayEnd.getTime()) {
        plannedToday.push(taskToJSON(task));
      } else if (plannedDate.getTime() <= weekEnd.getTime()) {
        plannedSoon.push(taskToJSON(task));
      }
    }
  }
  return {overdue: overdue, today: today, flagged: flagged, dueThisWeek: dueThisWeek, plannedToday: plannedToday, plannedSoon: plannedSoon, forecastTagged: forecastTagged};
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
  if (params.endDate !== undefined) {
    var ed = parseDate(params.endDate);
    if (ed) { safeSet(task, 'repetitionEndDate', ed); }
    if (params.endDate === null) { safeSet(task, 'repetitionEndDate', null); }
  }
  if (params.maxOccurrences !== undefined) {
    if (params.maxOccurrences === null) {
      safeSet(task, 'maxRepetitions', null);
    } else {
      safeSet(task, 'maxRepetitions', params.maxOccurrences);
    }
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
  var due = firstValue(task, ['dueDate']);
  var defer = firstValue(task, ['deferDate']);
  var project = doc.make({new: 'project', withProperties: {name: name}});
  if (note) { safeSet(project, 'note', note); }
  if (flagged) { safeSet(project, 'flagged', flagged); }
  if (due) { safeSet(project, 'dueDate', due); }
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
  var finalTags = [];
  try { finalTags = arrayify(task.tags()); } catch (e) { try { finalTags = arrayify(task.tags); } catch (e2) {} }
  var result = taskToJSON(task);
  if (finalTags.length < newTags.length) {
    result.warnings = ['Some tags were not applied after reorder (mutually exclusive tags may have been rejected). Requested: ' + newTags.length + ', applied: ' + finalTags.length];
  }
  return result;
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

function revealItem(params) {
  var doc = getDocument();
  var id = normalizeId(params.id);
  var obj = null;
  var typeName = '';

  obj = findTaskById(doc, id);
  if (obj) { typeName = 'task'; }
  if (!obj) { obj = findProjectById(doc, id); if (obj) typeName = 'project'; }
  if (!obj) { obj = findTagById(doc, id); if (obj) typeName = 'tag'; }
  if (!obj) { obj = findFolderById(doc, id); if (obj) typeName = 'folder'; }
  if (!obj) { throw new Error('Item not found: ' + params.id); }

  // Use omnifocus:/// URL scheme to reveal the item
  var urlStr = 'omnifocus:///' + typeName + '/' + id;
  var app = Application.currentApplication();
  app.includeStandardAdditions = true;
  try {
    app.openLocation(urlStr);
    return {revealed: true, type: typeName, id: id, url: urlStr};
  } catch (e) {
    return {revealed: false, type: typeName, id: id, url: urlStr, reason: e.message};
  }
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
  case 'reveal':
    result = revealItem(params);
    break;
  default:
    throw new Error('Unknown action: ' + action);
}

console.log(JSON.stringify(result));
