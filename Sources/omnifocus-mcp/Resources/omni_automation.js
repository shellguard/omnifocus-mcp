(function() {



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

// === Shared Utilities (from JSShared.swift, inlined here for single-string execution) ===

// __SHARED_JS__

// === End Shared Utilities ===




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
