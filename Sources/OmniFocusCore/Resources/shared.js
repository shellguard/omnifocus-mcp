
function toISO(date) {
  try {
    if (!date) { return null; }
    if (typeof date === 'string') { return date; }
    if (typeof date.toISOString === 'function') { return date.toISOString(); }
    var d = new Date(date);
    return isNaN(d.getTime()) ? null : d.toISOString();
  } catch (e) {
    return null;
  }
}

function safeCall(obj, prop) {
  if (!obj) { return null; }
  try {
    var v = obj[prop];
    if (typeof v === 'function') {
      return v.call(obj);
    }
    return v !== undefined ? v : null;
  } catch (e) {
    return null;
  }
}

function safeSet(obj, prop, value) {
  if (!obj) { return false; }
  try {
    if (typeof obj[prop] === 'function') {
      return false;
    }
    obj[prop] = value;
    return true;
  } catch (e) {
  }
  return false;
}

function firstValue(obj, names) {
  for (var i = 0; i < names.length; i++) {
    var v = safeCall(obj, names[i]);
    if (v !== null && v !== undefined) {
      return v;
    }
  }
  return null;
}

function arrayify(value) {
  if (!value) { return []; }
  if (Array.isArray(value)) { return value; }
  try {
    if (typeof value.length === 'number') {
      var arr = [];
      for (var i = 0; i < value.length; i++) {
        arr.push(value[i]);
      }
      return arr;
    }
  } catch (e) {}
  try {
    if (typeof value === 'function') {
      return arrayify(value());
    }
  } catch (e) {}
  return [value];
}

function normalizeStatus(status) {
  if (!status) { return null; }
  status = String(status).toLowerCase();
  if (status.indexOf('active') !== -1) { return 'active'; }
  if (status.indexOf('on hold') !== -1 || status.indexOf('hold') !== -1 || status.indexOf('onhold') !== -1 || status === 'inactive') { return 'on_hold'; }
  if (status.indexOf('done') !== -1 || status.indexOf('completed') !== -1) { return 'completed'; }
  if (status.indexOf('dropped') !== -1 || status.indexOf('drop') !== -1) { return 'dropped'; }
  return status;
}

function dateValue(value) {
  if (!value) { return null; }
  if (value instanceof Date) {
    return isNaN(value.getTime()) ? null : value;
  }
  if (typeof value === 'string') {
    var d = new Date(value);
    return isNaN(d.getTime()) ? null : d;
  }
  if (typeof value === 'number') {
    var d2 = new Date(value);
    return isNaN(d2.getTime()) ? null : d2;
  }
  return null;
}

function isTaskAvailable(task) {
  if (safeCall(task, 'completed')) { return false; }
  if (safeCall(task, 'dropped')) { return false; }
  var deferDate = dateValue(firstValue(task, ['deferDate', 'effectiveDeferDate']));
  if (deferDate && deferDate > new Date()) { return false; }
  return true;
}

function isTaskOverdue(task) {
  if (safeCall(task, 'completed')) { return false; }
  var dueDate = dateValue(firstValue(task, ['dueDate', 'effectiveDueDate']));
  if (!dueDate) { return false; }
  return dueDate < new Date();
}

function tagNames(task) {
  try {
    var tags = arrayify(firstValue(task, ['tags']));
    return tags.map(function(t) { return safeCall(t, 'name'); }).filter(function(n) { return n; });
  } catch (e) {
    return [];
  }
}

function projectName(task) {
  try {
    var p = firstValue(task, ['containingProject', 'project', 'assignedContainer']);
    return p ? safeCall(p, 'name') : null;
  } catch (e) {
    return null;
  }
}

function normalizeTaskStatus(ts) {
  if (ts === null || ts === undefined) { return null; }
  var s = String(ts).toLowerCase();
  if (s.indexOf('available') !== -1) { return 'available'; }
  if (s.indexOf('completed') !== -1) { return 'completed'; }
  if (s.indexOf('dropped') !== -1) { return 'dropped'; }
  if (s.indexOf('blocked') !== -1) { return 'blocked'; }
  if (s.indexOf('duesoon') !== -1) { return 'dueSoon'; }
  if (s.indexOf('next') !== -1) { return 'next'; }
  if (s.indexOf('overdue') !== -1) { return 'overdue'; }
  return s;
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

function appendNote(obj, text) {
  if (!text) { return; }
  var existing = safeCall(obj, 'note') || '';
  var separator = existing ? '\n' : '';
  safeSet(obj, 'note', existing + separator + text);
}

function enumString(value) {
  if (value === null || value === undefined) { return null; }
  return String(value);
}

function repetitionRuleToJSON(rule) {
  if (!rule) { return null; }
  if (typeof rule === 'string') {
    return { ruleString: rule, catchUpAutomatically: null, scheduleType: null, anchorDateKey: null, method: null };
  }
  return {
    ruleString: safeCall(rule, 'ruleString'),
    catchUpAutomatically: safeCall(rule, 'catchUpAutomatically'),
    scheduleType: enumString(safeCall(rule, 'scheduleType')),
    anchorDateKey: enumString(safeCall(rule, 'anchorDateKey')),
    method: enumString(safeCall(rule, 'method'))
  };
}

function parseOmniFocusUrl(urlStr) {
  var result = { url: urlStr || null, type: null, id: null, query: {} };
  if (!urlStr || typeof urlStr !== 'string') { return result; }
  try {
    var qIndex = urlStr.indexOf('?');
    var base = qIndex >= 0 ? urlStr.slice(0, qIndex) : urlStr;
    var query = qIndex >= 0 ? urlStr.slice(qIndex + 1) : '';
    var path = base.replace(/^omnifocus:\/\//i, '').replace(/^\/+/, '');
    var parts = path.split('/');
    if (parts[0]) { result.type = parts[0]; }
    if (parts[1]) { result.id = parts[1]; }
    if (query) {
      var pairs = query.split('&');
      for (var i = 0; i < pairs.length; i++) {
        if (!pairs[i]) { continue; }
        var eq = pairs[i].indexOf('=');
        var key = eq >= 0 ? pairs[i].slice(0, eq) : pairs[i];
        var val = eq >= 0 ? pairs[i].slice(eq + 1) : '';
        try { key = decodeURIComponent(key); } catch (e) {}
        try { val = decodeURIComponent(val.replace(/\+/g, ' ')); } catch (e2) {}
        if (key) { result.query[key] = val; }
      }
    }
  } catch (e) {}
  return result;
}
