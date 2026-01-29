(function (global, factory) {
  typeof exports === 'object' && typeof module !== 'undefined' ? module.exports = factory() :
    typeof define === 'function' && define.amd ? define(factory) :
      (global = typeof globalThis !== 'undefined' ? globalThis : global || self, global.Danmaku = factory());
}(this, (function () {
  'use strict';

  var transform = (function () {
    /* istanbul ignore next */
    if (typeof document === 'undefined') return 'transform';
    var properties = [
      'oTransform', // Opera 11.5
      'msTransform', // IE 9
      'mozTransform',
      'webkitTransform',
      'transform'
    ];
    var style = document.createElement('div').style;
    for (var i = 0; i < properties.length; i++) {
      /* istanbul ignore else */
      if (properties[i] in style) {
        return properties[i];
      }
    }
    /* istanbul ignore next */
    return 'transform';
  }());

  var dpr = typeof window !== 'undefined' && window.devicePixelRatio || 1;

  var canvasHeightCache = Object.create(null);

  function canvasHeight(font, fontSize) {
    if (canvasHeightCache[font]) {
      return canvasHeightCache[font];
    }
    var height = 12;
    var regex = /(\d+(?:\.\d+)?)(px|%|em|rem)(?:\s*\/\s*(\d+(?:\.\d+)?)(px|%|em|rem)?)?/;
    var p = font.match(regex);
    if (p) {
      var fs = p[1] * 1 || 10;
      var fsu = p[2];
      var lh = p[3] * 1 || 1.2;
      var lhu = p[4];
      if (fsu === '%') fs *= fontSize.container / 100;
      if (fsu === 'em') fs *= fontSize.container;
      if (fsu === 'rem') fs *= fontSize.root;
      if (lhu === 'px') height = lh;
      if (lhu === '%') height = fs * lh / 100;
      if (lhu === 'em') height = fs * lh;
      if (lhu === 'rem') height = fontSize.root * lh;
      if (lhu === undefined) height = fs * lh;
    }
    canvasHeightCache[font] = height;
    return height;
  }

  function createCommentCanvas(cmt, fontSize) {
    if (typeof cmt.render === 'function') {
      var cvs = cmt.render();
      if (cvs instanceof HTMLCanvasElement) {
        cmt.width = cvs.width;
        cmt.height = cvs.height;
        return cvs;
      }
    }
    var canvas = document.createElement('canvas');
    var ctx = canvas.getContext('2d');
    var style = cmt.style || {};
    style.font = `${danmakufsBase * 10}px sans-serif`;
    ////console.log('style.font:',style.font);
    style.textBaseline = style.textBaseline || 'bottom';
    style.lineWidth = lineWidth;
    var strokeWidth = style.lineWidth * 1;
    strokeWidth = (strokeWidth > 0 && strokeWidth !== Infinity)
      ? Math.ceil(strokeWidth)
      : !!style.strokeStyle * 1;
    ctx.font = style.font;
    cmt.width = cmt.width ||
      Math.max(1, Math.ceil(ctx.measureText(cmt.text).width) + strokeWidth * 2);
    cmt.height = cmt.height ||
      Math.ceil(canvasHeight(style.font, fontSize)) + strokeWidth * 2;
    canvas.width = cmt.width * dpr;
    canvas.height = cmt.height * dpr;
    ctx.scale(dpr, dpr);
    for (var key in style) {
      ctx[key] = style[key];
    }
    var baseline = 0;
    switch (style.textBaseline) {
      case 'top':
      case 'hanging':
        baseline = strokeWidth;
        break;
      case 'middle':
        baseline = cmt.height >> 1;
        break;
      default:
        baseline = cmt.height - strokeWidth;
    }
    if (style.strokeStyle) {
      ctx.strokeText(cmt.text, strokeWidth, baseline);
    }
    ctx.fillText(cmt.text, strokeWidth, baseline);
    return canvas;
  }

  function computeFontSize(el) {
    return window
      .getComputedStyle(el, null)
      .getPropertyValue('font-size')
      .match(/(.+)px/)[1] * 1;
  }

  function init(container) {
    var stage = document.createElement('canvas');
    stage.context = stage.getContext('2d');
    stage._fontSize = {
      root: computeFontSize(document.getElementsByTagName('html')[0]),
      container: computeFontSize(container)
    };
    return stage;
  }

  function clear(stage, comments) {
    stage.context.clearRect(0, 0, stage.width, stage.height);
    // avoid caching canvas to reduce memory usage
    for (var i = 0; i < comments.length; i++) {
      comments[i].canvas = null;
    }
  }

  function resize(stage, width, height) {
    stage.width = width * dpr;
    stage.height = height * dpr;
    stage.style.width = width + 'px';
    stage.style.height = height + 'px';
  }

  function framing(stage) {
    stage.context.clearRect(0, 0, stage.width, stage.height);
  }

  function setup(stage, comments) {
    for (var i = 0; i < comments.length; i++) {
      var cmt = comments[i];
      cmt.canvas = createCommentCanvas(cmt, danmakufsBase * 10);
    }
  }

  function render(stage, cmt) {
    if (DanmakuOff === 0) {
      return; // 直接跳过，不渲染
    }

    // 如果是底部弹幕且 BottomAlpha 为 0，则不渲染
    if (cmt.mode === 'bottom' && BottomAlpha === 0) {
      return; // 直接跳过，不渲染
    }

    // 如果是顶部弹幕且 TopAlpha 为 0，则不渲染
    if (cmt.mode === 'top' && TopAlpha === 0) {
      return; // 直接跳过，不渲染
    }

    // 如果是右到左的弹幕且 RtlAlpha 为 0，则不渲染
    if (cmt.mode === 'rtl' && RtlAlpha === 0) {
      return; // 直接跳过，不渲染
    }



    // 正常渲染其他弹幕
    if (cmt.canvas) {
      stage.context.drawImage(cmt.canvas, cmt.x * dpr, cmt.y * dpr);
    }
  }

  function remove(stage, cmt) {
    // avoid caching canvas to reduce memory usage
    cmt.canvas = null;
  }

  var canvasEngine = {
    name: 'canvas',
    init: init,
    clear: clear,
    resize: resize,
    framing: framing,
    setup: setup,
    render: render,
    remove: remove,
  };

  /* eslint no-invalid-this: 0 */
  function allocate(cmt) {
    var that = this;
    var ct = this.media ? this.media.currentTime : Date.now() / 1000;
    var pbr = this.media ? this.media.playbackRate : 1;
    function willCollide(cr, cmt) {
      if (cmt.mode === 'top' || cmt.mode === 'bottom') {
        return ct - cr.time < that._.duration;
      }
      var crTotalWidth = that._.width + cr.width;
      var crElapsed = crTotalWidth * (ct - cr.time) * pbr / that._.duration;
      if (cr.width > crElapsed) {
        return true;
      }
      // (rtl mode) the right end of `cr` move out of left side of stage
      var crLeftTime = that._.duration + cr.time - ct;
      var cmtTotalWidth = that._.width + cmt.width;
      var cmtTime = that.media ? cmt.time : cmt._utc;
      var cmtElapsed = cmtTotalWidth * (ct - cmtTime) * pbr / that._.duration;
      var cmtArrival = that._.width - cmtElapsed;
      // (rtl mode) the left end of `cmt` reach the left side of stage
      var cmtArrivalTime = that._.duration * cmtArrival / (that._.width + cmt.width);
      return crLeftTime > cmtArrivalTime;
    }
    var crs = this._.space[cmt.mode];
    var last = 0;
    var curr = 0;
    for (var i = 1; i < crs.length; i++) {
      var cr = crs[i];
      var requiredRange = cmt.height;
      if (cmt.mode === 'top' || cmt.mode === 'bottom') {
        requiredRange += cr.height;
      }
      if (cr.range - cr.height - crs[last].range >= requiredRange) {
        curr = i;
        break;
      }
      if (willCollide(cr, cmt)) {
        last = i;
      }
    }
    var channel = crs[last].range;
    // 计算最终分配的 y 坐标
    var finalY = channel % (this._.height - cmt.height);

    // 限制 y 坐标在屏幕前 1/4 的范围内
    var maxAllowedHeight = this._.height / 4*RenderRegion;  // 屏幕的1/4高度
    if (finalY > maxAllowedHeight) {
      return -1;  // 超过1/4屏幕高度，停止进一步操作
    }
    var crObj = {
      range: channel + cmt.height,
      time: this.media ? cmt.time : cmt._utc,
      width: cmt.width,
      height: cmt.height
    };
    crs.splice(last + 1, curr - last - 1, crObj);

    if (cmt.mode === 'bottom') {
      return this._.height - cmt.height - channel % this._.height;
    }
    return channel % (this._.height - cmt.height);
  }

  /* eslint no-invalid-this: 0 */
  function createEngine(framing, setup, render, remove) {
    return function () {
      framing(this._.stage);
      var dn = Date.now() / 1000;
      var ct = this.media ? this.media.currentTime : dn;
      var pbr = this.media ? this.media.playbackRate : 1;
      var cmt = null;
      var cmtt = 0;
      var i = 0;
      for (i = this._.runningList.length - 1; i >= 0; i--) {
        cmt = this._.runningList[i];
        cmtt = this.media ? cmt.time : cmt._utc;
        if (ct - cmtt > this._.duration) {
          remove(this._.stage, cmt);
          this._.runningList.splice(i, 1);
        }
      }
      var pendingList = [];
      while (this._.position < this.comments.length) {
        cmt = this.comments[this._.position];
        cmtt = this.media ? cmt.time : cmt._utc;
        if (cmtt >= ct) {
          break;
        }
        // when clicking controls to seek, media.currentTime may changed before
        // `pause` event is fired, so here skips comments out of duration,
        // see https://github.com/weizhenye/Danmaku/pull/30 for details.
        if (ct - cmtt > this._.duration) {
          ++this._.position;
          continue;
        }
        if (this.media) {
          cmt._utc = dn - (this.media.currentTime - cmt.time);
        }
        pendingList.push(cmt);
        ++this._.position;
      }
      setup(this._.stage, pendingList);
      for (i = 0; i < pendingList.length; i++) {
        cmt = pendingList[i];
        cmt.y = allocate.call(this, cmt);
        this._.runningList.push(cmt);
      }
      for (i = 0; i < this._.runningList.length; i++) {
        cmt = this._.runningList[i];
        var totalWidth = this._.width + cmt.width;
        var elapsed = totalWidth * (dn - cmt._utc) * pbr / this._.duration;
        if (cmt.mode === 'ltr') cmt.x = (elapsed - cmt.width + .5) | 0;
        if (cmt.mode === 'rtl') cmt.x = (this._.width - elapsed + .5) | 0;
        if (cmt.mode === 'top' || cmt.mode === 'bottom') {
          cmt.x = (this._.width - cmt.width) >> 1;
        }
        render(this._.stage, cmt);
      }
    };
  }

  var raf =
    (
      typeof window !== 'undefined' &&
      (
        window.requestAnimationFrame ||
        window.mozRequestAnimationFrame ||
        window.webkitRequestAnimationFrame
      )
    ) ||
    function (cb) {
      return setTimeout(cb, 50 / 3);
    };

  var caf =
    (
      typeof window !== 'undefined' &&
      (
        window.cancelAnimationFrame ||
        window.mozCancelAnimationFrame ||
        window.webkitCancelAnimationFrame
      )
    ) ||
    clearTimeout;

  function binsearch(arr, prop, key) {
    var mid = 0;
    var left = 0;
    var right = arr.length;
    while (left < right - 1) {
      mid = (left + right) >> 1;
      if (key >= arr[mid][prop]) {
        left = mid;
      } else {
        right = mid;
      }
    }
    if (arr[left] && key < arr[left][prop]) {
      return left;
    }
    return right;
  }


  function formatMode(mode) {
    if (!/^(ltr|top|bottom)$/i.test(mode)) {
      return 'rtl';
    }
    return mode.toLowerCase();
  }

  function collidableRange() {
    var max = 9007199254740991;
    return [
      { range: 0, time: -max, width: max, height: 0 },
      { range: max, time: max, width: 0, height: 0 }
    ];
  }

  function resetSpace(space) {
    space.ltr = collidableRange();
    space.rtl = collidableRange();
    space.top = collidableRange();
    space.bottom = collidableRange();
  }

  /* eslint no-invalid-this: 0 */
  function play() {
    if (!this._.visible || !this._.paused) {
      return this;
    }
    this._.paused = false;
    if (this.media) {
      for (var i = 0; i < this._.runningList.length; i++) {
        var cmt = this._.runningList[i];
        cmt._utc = Date.now() / 1000 - (this.media.currentTime - cmt.time);
      }
    }
    var that = this;
    var engine = createEngine(
      this._.engine.framing.bind(this),
      this._.engine.setup.bind(this),
      this._.engine.render.bind(this),
      this._.engine.remove.bind(this)
    );
    function frame() {
      engine.call(that);
      that._.requestID = raf(frame);
    }
    this._.requestID = raf(frame);
    return this;
  }

  /* eslint no-invalid-this: 0 */
  function pause() {
    if (!this._.visible || this._.paused) {
      return this;
    }
    this._.paused = true;
    caf(this._.requestID);
    this._.requestID = 0;
    return this;
  }

  /* eslint no-invalid-this: 0 */
  function seek() {
    if (!this.media) {
      return this;
    }
    this.clear();
    resetSpace(this._.space);
    var position = binsearch(this.comments, 'time', this.media.currentTime);
    this._.position = Math.max(0, position - 1);
    return this;
  }

  /* eslint no-invalid-this: 0 */
  function bindEvents(_) {
    _.play = play.bind(this);
    _.pause = pause.bind(this);
    _.seeking = seek.bind(this);
    this.media.addEventListener('play', _.play);
    this.media.addEventListener('pause', _.pause);
    this.media.addEventListener('playing', _.play);
    this.media.addEventListener('waiting', _.pause);
    this.media.addEventListener('seeking', _.seeking);
  }

  /* eslint no-invalid-this: 0 */
  function unbindEvents(_) {
    this.media.removeEventListener('play', _.play);
    this.media.removeEventListener('pause', _.pause);
    this.media.removeEventListener('playing', _.play);
    this.media.removeEventListener('waiting', _.pause);
    this.media.removeEventListener('seeking', _.seeking);
    _.play = null;
    _.pause = null;
    _.seeking = null;
  }

  /* eslint-disable no-invalid-this */
  function init$1(opt) {
    this._ = {};
    this.container = opt.container || document.createElement('div');
    this.media = opt.media;
    this._.visible = true;
    /* istanbul ignore next */
    {
      this.engine = 'canvas';
      this._.engine = canvasEngine;
    }
    /* eslint-enable no-undef */
    this._.requestID = 0;

    this._.speed = Math.max(0, opt.speed) || 144;
    this._.duration = 4;

    this.comments = opt.comments || [];
    this.comments.sort(function (a, b) {
      return a.time - b.time;
    });
    for (var i = 0; i < this.comments.length; i++) {
      this.comments[i].mode = formatMode(this.comments[i].mode);
    }
    this._.runningList = [];
    this._.position = 0;

    this._.paused = true;
    if (this.media) {
      this._.listener = {};
      bindEvents.call(this, this._.listener);
    }

    this._.stage = this._.engine.init(this.container);
    this._.stage.style.cssText += 'position:relative;pointer-events:none;';

    this.resize();
    this.container.appendChild(this._.stage);

    this._.space = {};
    resetSpace(this._.space);

    if (!this.media || !this.media.paused) {
      seek.call(this);
      play.call(this);
    }
    return this;
  }

  /* eslint-disable no-invalid-this */
  function destroy() {
    if (!this.container) {
      return this;
    }

    pause.call(this);
    this.clear();
    this.container.removeChild(this._.stage);
    if (this.media) {
      unbindEvents.call(this, this._.listener);
    }
    for (var key in this) {
      /* istanbul ignore else  */
      if (Object.prototype.hasOwnProperty.call(this, key)) {
        this[key] = null;
      }
    }
    return this;
  }

  var properties = ['mode', 'time', 'text', 'render', 'style'];

  /* eslint-disable no-invalid-this */
  function emit(obj) {
    if (!obj || Object.prototype.toString.call(obj) !== '[object Object]') {
      return this;
    }
    var cmt = {};
    for (var i = 0; i < properties.length; i++) {
      if (obj[properties[i]] !== undefined) {
        cmt[properties[i]] = obj[properties[i]];
      }
    }
    cmt.text = (cmt.text || '').toString();
    cmt.mode = formatMode(cmt.mode);
    cmt._utc = Date.now() / 1000;
    if (this.media) {
      var position = 0;
      if (cmt.time === undefined) {
        cmt.time = this.media.currentTime;
        position = this._.position;
      } else {
        position = binsearch(this.comments, 'time', cmt.time);
        if (position < this._.position) {
          this._.position += 1;
        }
      }
      this.comments.splice(position, 0, cmt);
    } else {
      this.comments.push(cmt);
    }
    return this;
  }

  /* eslint-disable no-invalid-this */
  function show() {
    if (this._.visible) {
      return this;
    }
    this._.visible = true;
    if (this.media && this.media.paused) {
      return this;
    }
    seek.call(this);
    play.call(this);
    return this;
  }

  /* eslint-disable no-invalid-this */
  function hide() {
    if (!this._.visible) {
      return this;
    }
    pause.call(this);
    this.clear();
    this._.visible = false;
    return this;
  }

  /* eslint-disable no-invalid-this */
  function clear$1() {
    this._.engine.clear(this._.stage, this._.runningList);
    this._.runningList = [];
    return this;
  }

  /* eslint-disable no-invalid-this */
  function resize$1() {
    this._.width = this.container.offsetWidth;
    this._.height = this.container.offsetHeight;
    this._.engine.resize(this._.stage, this._.width, this._.height);
    this._.duration = this._.width / this._.speed;
    return this;
  }

  var speed = {
    get: function () {
      return this._.speed;
    },
    set: function (s) {
      if (typeof s !== 'number' ||
        isNaN(s) ||
        !isFinite(s) ||
        s <= 0) {
        return this._.speed;
      }
      this._.speed = s;
      if (this._.width) {
        this._.duration = this._.width / s;
      }
      return s;
    }
  };

  function Danmaku(opt) {
    opt && init$1.call(this, opt);
  }
  Danmaku.prototype.destroy = function () {
    return destroy.call(this);
  };
  Danmaku.prototype.emit = function (cmt) {
    return emit.call(this, cmt);
  };
  Danmaku.prototype.show = function () {
    return show.call(this);
  };
  Danmaku.prototype.hide = function () {
    return hide.call(this);
  };
  Danmaku.prototype.clear = function () {
    return clear$1.call(this);
  };
  Danmaku.prototype.resize = function () {
    return resize$1.call(this);
  };
  Object.defineProperty(Danmaku.prototype, 'speed', speed);

  return Danmaku;

})));
