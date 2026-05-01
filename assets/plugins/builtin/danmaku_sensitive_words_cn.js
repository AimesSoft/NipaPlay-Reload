const pluginManifest = {
  id: 'builtin.cn_sensitive_danmaku_filter',
  name: '弹幕预设屏蔽词（中国大陆）',
  version: '1.1.0',
  description: '内置常用敏感词与辱骂词，启用后自动屏蔽命中的弹幕。',
  author: 'NipaPlay Team',
  github: 'https://github.com/AimesSoft/nipaplay-reload'
};

const pluginBlockWordsBase64 =
    'WyLlj7Dni6wiLCLmuK/ni6wiLCLol4/ni6wiLCLnlobni6wiLCLms5Xova7lip8iLCLova7lrZAiLCI2NOS6i+S7tiIsIuWFreWbmyIsIuWPjeWFsSIsIueyvuaXpSIsIuaUr+mCoyIsIueLl+axieWluCIsIuatu+WmiCIsIuS9oOWmiOatu+S6hiIsIuWCu+mAvCIsIueFnueslCIsIuiEkeauiyIsIuW6n+eJqSIsIua7muWHuuWOuyIsIuWOu+atuyIsIuaTjeS9oOWmiCIsIuiPieazpemprCIsIuWmiOeahOaZuumanCIsIui0seS6uiIsIueVnOeUnyIsIuS6uua4oyIsIuWeg+WcvueOqeaEjyIsIuWPjeS6uuexuyIsIuaBkOaAluiireWHuyIsIueCuOWtpuagoSIsIueCuOWcsOmTgSIsIueCuOmjnuacuiIsIuWIgOS6uiIsIuiHquWItueCuOW8uSIsIuWMluWtpuatpuWZqCIsIue6pueCriIsIuaPtOS6pCIsIuWkp+S/neWBpSIsIum7hOeJhyIsIkFW5aWz5LyYIiwi5by65aW4Iiwi6L2u5aW4Iiwi5pyq5oiQ5bm26Imy5oOFIiwi5byA55uSIiwi5Lq66IKJ5pCc57SiIiwi6Lqr5Lu96K+B5Y+3Iiwi5omL5py65Y+3Iiwi5L2P5Z2A5pud5YWJIiwi572R6LWMIiwi5Yi35Y2V6K+I6aqXIiwi5rSX6ZKxIiwi5p2A54yq55uYIiwi5Yaw5q+SIiwi5rW35rSb5ZugIiwiS+eyiSIsIuWkp+m6u+S6pOaYkyIsIk5NU0wiLCJTQiIsIkNOTSJd';

function decodeBase64Utf8(input) {
  if (!input) {
    return '';
  }
  if (typeof atob === 'function') {
    const binary = atob(input);
    let bytes = '';
    for (let i = 0; i < binary.length; i += 1) {
      bytes += '%' + ('00' + binary.charCodeAt(i).toString(16)).slice(-2);
    }
    return decodeURIComponent(bytes);
  }
  if (typeof Buffer !== 'undefined') {
    return Buffer.from(input, 'base64').toString('utf8');
  }
  throw new Error('当前 JS 运行时不支持 base64 解码');
}

function parseBlockWords() {
  const jsonText = decodeBase64Utf8(pluginBlockWordsBase64);
  const parsed = JSON.parse(jsonText);
  if (!Array.isArray(parsed)) {
    return [];
  }
  return parsed
    .map((item) => String(item || '').trim())
    .filter((item) => item.length > 0);
}

const pluginBlockWords = parseBlockWords();

const pluginUIEntries = [
  {
    id: 'preview_words',
    title: '已生效词库预览',
    description: '查看本插件当前生效的内置屏蔽词。'
  }
];

function pluginHandleUIAction(actionId) {
  if (actionId !== 'preview_words') {
    return {
      type: 'text',
      title: '插件操作',
      content: '不支持的操作。'
    };
  }

  const words = pluginBlockWords;
  return {
    type: 'text',
    title: '已生效词库预览',
    content: words.length > 0
      ? '共 ' + words.length + ' 条：\n' + words.join('、')
      : '当前没有可用屏蔽词。'
  };
}
