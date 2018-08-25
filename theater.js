var theater = null;
var past = [];
var present = null;
var future = [];
var timeout = 0;
var timeoutIsRedo = false;
var startFocused = false;

function createScene(index, frame) {
  var scene = document.createElement("textarea");
  scene.style.position = "absolute";
  scene.style.top = "0";
  scene.style.left = "0";
  scene.style.width = "100%";
  scene.style.height = "100%";
  scene.style.resize = "none";
  scene.style.overflow = "hidden";
  scene.style.boxSizing = "border-box";
  scene.style.padding = "8px";
  scene.style.borderWidth = "2px";
  scene.style.margin = "0";
  scene.style.font = "inherit";
  scene.style.background = "transparent";
  scene.style.visibility = "visible";
  scene.dataset.gramm_editor = "false";
  scene.spellcheck = false;
  scene.value = frame.text;
  scene.firstFrame = frame;
  scene.lastFrame = null;
  scene.index = index;
  scene.addEventListener("keydown", handleKeydown);
  scene.addEventListener("input", handleInput);
  return scene;
}

function hideScene(scene) {
  scene.style.visibility = "hidden";
}

function showScene(scene) {
  scene.style.visibility = "visible";
}

function initTheater(frame) {
  if (theater == null) {
    theater = document.getElementById("theater");
  } else {
    startFocused = document.activeElement === present;

    past = [];
    present = null;
    future = [];
    while (theater.firstChild) {
      theater.removeChild(theater.firstChild);
    }

    if (timeout != 0) {
      clearTimeout(timeout);
      timeout = 0;
    }
  }

  present = createScene(0, frame);
  theater.appendChild(present);
  if (startFocused) {
    present.focus();
  }
}

function focusTheater() {
  if (present == null) {
    startFocused = true;
  } else {
    present.focus();
  }
}

function replace(replacement) {
  var focused = document.activeElement === present;

  for (var i = 0; i < future.length; i++) {
    theater.removeChild(future[i]);
  }
  future = [];

  present.lastFrame = {
    text: present.value,
    selectionStart: replacement.selectionStart,
    selectionEnd: replacement.selectionEnd
  };
  hideScene(present);
  past.push(present);

  var cursorPos = replacement.selectionStart + replacement.text.length;
  var frame = {
    text:
      present.value.substring(0, replacement.selectionStart) +
      replacement.text +
      present.value.substring(replacement.selectionEnd),
    selectionStart: cursorPos,
    selectionEnd: cursorPos
  };
  present = createScene(present.index + 1, frame);
  theater.appendChild(present);
  // Edge ignores selection changes if the textarea isn't
  // part of the DOM yet
  present.selectionStart = frame.selectionStart;
  present.selectionEnd = frame.selectionEnd;
  if (focused) {
    present.focus();
  }
}

function undoAndReplace(replacement) {
  var focused = document.activeElement === present;

  for (var i = 0; i < future.length; i++) {
    theater.removeChild(future[i]);
  }
  future = [];
  theater.removeChild(present);

  var previous = past[past.length - 1];
  previous.lastFrame = {
    text: previous.value,
    selectionStart: replacement.selectionStart,
    selectionEnd: replacement.selectionEnd
  };

  var cursorPos = replacement.selectionStart + replacement.text.length;
  var frame = {
    text:
      previous.value.substring(0, replacement.selectionStart) +
      replacement.text +
      previous.value.substring(replacement.selectionEnd),
    selectionStart: cursorPos,
    selectionEnd: cursorPos
  };
  present = createScene(present.index, frame);
  theater.appendChild(present);
  present.selectionStart = frame.selectionStart;
  present.selectionEnd = frame.selectionEnd;
  if (focused) {
    present.focus();
  }
}

function hardUndo() {
  var focused = document.activeElement === present;

  for (var i = 0; i < future.length; i++) {
    theater.removeChild(future[i]);
  }
  future = [];
  theater.removeChild(present);

  present = past.pop();
  present.lastFrame = null;
  showScene(present);
  if (focused) {
    present.focus();
  }
}

function undo() {
  if (past.length == 0) {
    return;
  }

  var focused = document.activeElement === present;

  hideScene(present);
  future.push(present);

  present = past.pop();
  showScene(present);
  present.selectionStart = present.lastFrame.selectionStart
  present.selectionEnd = present.lastFrame.selectionEnd
  if (focused) {
    present.focus();
  }
}

function redo() {
  if (future.length == 0) {
    return;
  }

  var focused = document.activeElement === present;

  hideScene(present);
  past.push(present);

  present = future.pop();
  showScene(present);
  present.selectionStart = present.firstFrame.selectionStart
  present.selectionEnd = present.firstFrame.selectionEnd
  if (focused) {
    present.focus();
  }
}

function timeoutWrapper(f) {
  return function() {
    timeout = 0;
    f();
    app.ports.text.send(present.value);
  };
}

function handleKeydown(event) {
  if (
    (event.which == 90 || (event.which == 89 && !event.shiftKey)) &&
    event.ctrlKey != event.metaKey &&
    !event.altKey
  ) {
    if (event.which == 90 && !event.shiftKey) {
      handleUndo(event);
    } else {
      handleRedo(event);
    }
  }
}

function handleUndo(event) {
  var node = event.currentTarget;
  if (
    node.index == present.index &&
    node.value == node.firstFrame.text &&
    timeout == 0
  ) {
    timeout = setTimeout(timeoutWrapper(undo), 5);
    timeoutIsRedo = false;
  }
}

function handleRedo(event) {
  var node = event.currentTarget;
  if (
    node.index == present.index &&
    node.lastFrame != null &&
    node.value == node.lastFrame.text &&
    timeout == 0
  ) {
    timeout = setTimeout(timeoutWrapper(redo), 5);
    timeoutIsRedo = true;
  }
}

function handleInput(event) {
  var node = event.currentTarget;
  if (node.index == present.index) {
    if (timeout != 0) {
      // Check that value has changed because Firefox sends
      // an input event even when undo is disabled
      if (
        timeoutIsRedo ?
        node.value != node.lastFrame.text :
        node.value != node.firstFrame.text
      ) {
        clearTimeout(timeout);
        timeout = 0;
      }
    }

    app.ports.text.send(node.value);
  } else if (node.index < present.index) {
    if (node.value != node.lastFrame.text) {
      document.execCommand("redo", true, null);
    }
  } else if (node.index > present.index) {
    if (node.value != node.firstFrame.text) {
      document.execCommand("undo", true, null);
    }
  }
}
