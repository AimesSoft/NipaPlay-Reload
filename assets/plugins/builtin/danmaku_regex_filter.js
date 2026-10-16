var pluginManifest = {
  id: 'builtin.danmaku_regex_filter',
  name: '弹幕正则过滤规则预设',
  version: '1.3.0',
  minHostVersion: '1.10.3',
  description:
    '内置常用弹幕正则过滤规则，启用后自动屏蔽匹配的弹幕。' +
    '可在配置中逐条开关规则。' +
    '包含：刷屏重复、刷观看次数、日期考古、签到/打卡占位、加群宣传、有人在看、纯关键词。',
  author: 'Retr0',
  github: 'https://github.com/AimesSoft/nipaplay-reload'
};

// ---- 规则定义 ----
// 规则来源：https://www.xiaoheihe.cn/bbs/user_profile_share?user_id=e2b66abd2420&h_src=heyboxapp
// 格式：规则名称/正则表达式/
// 日期分隔符：使用 \x2f 而非裸 / ，避免与 名称/正则/ 外层分隔符冲突
var SEP = '[.。·、,，_\\-\\x2f／]';

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
    desc:
      '内嵌或整条的日期弹幕：2026.04.12、7/9/2012、2026-04-12、20260412、260619、' +
      '0922、06/19、6月19号、2026年4月12日、12。03、11,.10.21、2011_7_24、2012y7m28d、' +
      '23 12 30，以及日期加“补完/存活/留念”等（如 11.5.28补完、存活 6.3）',
    // 允许日期出现在弹幕任意位置，用 \b 限制紧凑数字避免误伤 2333、10086 等
    pattern:
      '(?:' +
      '\\d{1,2}\\s*' + SEP + '\\s*\\d{1,2}\\s*' + SEP + '\\s*(?:19|20)\\d{2}' +           // 7/9/2012（月/日/年）
      '|\\b\\d{2,5}\\s*' + SEP + '{1,2}\\s*\\d{1,2}\\s*' + SEP + '{1,2}\\s*\\d{1,2}\\b' +   // 11.8.14、2014.6.2、20125-8-21、11,.10.21
      '|\\b(?:19|20)\\d{2}\\s*' + SEP + '\\s*\\d{1,2}\\b' +                               // 2014.6、2014. 8 .（年.月）
      '|\\b\\d{4}\\s*' + SEP + '\\s*\\d{3,4}\\b' +                                        // 2011.1204、2012.528（年.月日连写）
      '|\\b\\d{4}\\s*[yY]\\s*\\d{1,2}\\s*[mM]\\s*\\d{1,2}\\s*[dD]?\\b' +                    // 2012y7m28d
      '|\\b\\d{2,5}\\s*年\\s*\\d{1,2}\\s*月(?:\\s*\\d{1,2}\\s*[日号]?)?' +                    // 2014年8月、14年6月16号
      '|\\d{1,2}\\s*月\\s*\\d{1,2}\\s*[日号]' +                                            // 7月14号
      '|\\b(?:19|20)\\d{2}\\s*年' +                                                       // 2011年
      '|\\b\\d{4}\\s*除夕' +                                                             // 2014除夕
      '|\\b(?:19|20)\\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\\d|3[01])\\b' +                 // 20140315（8位紧凑）
      '|\\b\\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\\d|3[01])\\b' +                         // 130629（6位紧凑）
      '|\\b(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\\d|3[01])\\b' +                               // 0922（4位月日）
      '|\\b(?:19|20)\\d{2}\\b' +                                                        // 2013、2015 等年份
      '|\\b\\d{2}\\s+\\d{1,2}\\s+\\d{1,2}\\b' +                                          // 23 12 30（空格分隔）
      '|^\\s*(?:0?[1-9]|1[0-2])\\s*' + SEP + '\\s*(?:0?[1-9]|[12]\\d|3[01])\\s*$' +        // 整条 8.5、6/14、12。03
      '|(?:存活|补完|完结|撒花|纪念|留念|留恋|签到|打卡|考古|留名|路过|周目|补习|参上|确认)[^A-Za-z0-9]{0,6}(?:0?[1-9]|1[0-2])\\s*' + SEP + '\\s*(?:0?[1-9]|[12]\\d|3[01])' + // 存活 6.3、补完8.5
      '|(?:0?[1-9]|1[0-2])\\s*' + SEP + '\\s*(?:0?[1-9]|[12]\\d|3[01])[^A-Za-z0-9]{0,6}(?:存活|补完|完结|撒花|纪念|留念|留恋|签到|打卡|考古|留名|路过|周目|补习|参上|确认)' + // 6.12…补完
      ')/',
    enabled: true
  },
  {
    id: 'checkin',
    name: '打卡占位',
    desc:
      '整条仅由“补完/完结/撒花/存活/留念/留恋/纪念/留名/考古/签到/打卡/周目”等打卡词' +
      '与标点、数字组成、无实际内容的占位弹幕；带情感的如“补完了，值了啊”不受影响',
    pattern: '^(?=[\\s\\S]*?(?:补完|完结|撒花|存活|留念|留恋|纪念|留名|考古|路过|参上|签到|打卡|周目|存货|卍解|守望|确认|完毕))[补完完结撒花存活留念留恋纪念留名考古路过参上签到打卡周目存货卍解守望确认完毕彻底一二三四五六七八九十百千万两第次遍刷个+＋~～!！。.…、,，\\s\\d·:：\\-]*$/',
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
