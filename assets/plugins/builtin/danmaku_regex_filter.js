var pluginManifest = {
  id: 'danmaku_regex_filter',
  name: '弹幕正则过滤规则预设',
  version: '1.2.3',
  minHostVersion: '1.10.3',
  description:
    '内置常用弹幕正则过滤规则，启用后自动屏蔽匹配的弹幕。' +
    '可在配置中逐条开关规则。' +
    '包含：刷屏重复、刷观看次数、日期考古、签到占位、加群宣传、有人在看、纯关键词。',
  author: 'Retr0',
  github: 'https://github.com/AimesSoft/nipaplay-reload'
};

// ---- 规则定义 ----
// 规则来源：https://www.xiaoheihe.cn/bbs/user_profile_share?user_id=e2b66abd2420&h_src=heyboxapp
// 格式：规则名称/正则表达式/
var rules = [
  {
    id: 'repeat',
    name: '刷屏重复',
    desc: '重复字符、笑声刷屏、短语重复、超长弹幕（≥40字）',
    pattern: '[3啦嚯哦啊哈呵嘿嘻红惚火恍吼桀hw]{7,}|(\\S)\\1{6,}|(\\S{2,3}?)\\2{3,}|.{40,}/',
    enabled: true
  },
  {
    id: 'rewatch',
    name: '刷观看次数',
    desc: '"二刷""三周目"等刷存在感弹幕',
    pattern: '首刷|^我?(已经)?是?看?第?[\\d一二三四五六七八九十百千]+[个次遍]?(遍|次|周目|刷|观?看)(路过|完成|来)?[呀啊了耶的力哩咯]?[我人]?(路过)?(.*(觉得|感觉|想说|表示)*|[.。！!?~～]+)?$/',
    enabled: true
  },
  {
    id: 'date',
    name: '日期考古',
    desc: '各类日期格式弹幕（2026.04.12、2026/6/19、2026-04-12、20260412、260619、06/19、6月19号、2026年4月12日）及"考古/留名"等',
    pattern: '^(?:(?:\\d{2,4}[.\\x2f-]\\d{1,2}[.\\x2f-]\\d{1,2}|\\d{4}[.\\x2f-]\\d{3,4}|\\d{4}[.\\x2f-]\\d{1,2}|\\d{6}|\\d{8}|\\d{1,2}[.\\x2f-]\\d{1,2}|\\d{4}年\\d{1,2}月(?:\\d{1,2}[日号]?)?|\\d{1,2}月\\d{1,2}[日号]?)(?:[\\s　]+\\d{1,2}[:：点时]\\d{1,2}(?:[:：]\\d{1,2})?)?|\\d{2,4}[^]{0,10}?(?:路过|考古|留名|报[到道]|到此一游))$/',
    enabled: true
  },
  {
    id: 'anyone',
    name: '有人在看吗',
    desc: '"有没有人""有人在看吗"等无意义弹幕',
    pattern: '^(现在)?(是否)?(有?没)?[没有]人在?看?[不吗啊嘛么没]?[.。！!?？~～]*$/',
    enabled: true
  },
  {
    id: 'group',
    name: '加群宣传',
    desc: '"交流群""加群""QQ群"及带群号数字串的宣传弹幕',
    pattern: '(加群|交流群|[qQ]{1,2}群|水群|粉丝群|官方群|讨论群|弹幕群|福利群|扣群|群号|入群|进群|拉群|求群)|群[:：\\s]*\\d{5,}|\\d{5,}[:：\\s]*群|[qQ]{1,2}[:：\\s]*\\d{5,}|加.{0,3}[qQ]{1,2}/',
    enabled: true
  },
  {
    id: 'keyword',
    name: '纯关键词',
    desc: '"路过""打卡""前排""签到"等占位型弹幕及纯短数字',
    pattern: '^(上岸|秒[吃赤]|前排|好?早|烫|来[了啦]|热乎?的?|刚[刚来才]|接|到此一游|路过|插眼|打卡|留名|签个到|签[到个]?|签到|已签到?|标记|考古|测试|test|(关闭|开启|打开|启动|自动)?(字幕|翻译))+$|^[\\d]{1,3}$/',
    enabled: true
  }
];

// 根据启用状态生成 blockWords
function buildBlockWords() {
  var result = [];
  for (var i = 0; i < rules.length; i++) {
    if (rules[i].enabled) {
      result.push(rules[i].name + '/' + rules[i].pattern);
    }
  }
  return result;
}

var pluginBlockWords = buildBlockWords();

// 每条规则一个 UI 入口，带 enabled 状态供宿主渲染开关
function buildUIEntries() {
  var result = [];
  for (var i = 0; i < rules.length; i++) {
    result.push({
      id: rules[i].id,
      title: rules[i].name,
      description: rules[i].desc,
      enabled: rules[i].enabled
    });
  }
  return result;
}

var pluginUIEntries = buildUIEntries();

function pluginHandleUIAction(actionId) {
  // 查找对应规则并切换
  for (var i = 0; i < rules.length; i++) {
    if (rules[i].id === actionId) {
      rules[i].enabled = !rules[i].enabled;
      // 重建 blockWords 和 UI 入口
      pluginBlockWords = buildBlockWords();
      pluginUIEntries = buildUIEntries();
      var status = rules[i].enabled ? '已启用' : '已禁用';
      return {
        type: 'text',
        title: rules[i].name,
        content: status + '「' + rules[i].name + '」\n\n' + rules[i].desc
      };
    }
  }
  return {
    type: 'text',
    title: '弹幕正则过滤',
    content: '未知操作。'
  };
}
