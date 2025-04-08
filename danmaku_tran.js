// 修改 danmaku_tran.js 以支持模块化调用
const fs = require('fs');
const path = require('path');

function convertHexColorToCSS(hex) {
    // 将负数转换为无符号整数形式
    const unsignedHex = hex >>> 0;
    // 提取颜色部分（只保留 RGB）
    const colorHex = unsignedHex & 0xFFFFFF;
    // 转换为 CSS 格式
    return '#' + colorHex.toString(16).padStart(6, '0');
}
function escapeStringForJS(str) {
    return str
        .replace(/\"/g,"\"")
        .replace(/\\/g,'')
        .replace(/'/g, "\\'")    // 单引号
        .replace(/"/g, '\\"')    // 双引号
        .replace(/\r/g, '')   // 回车
        .replace(/\t/g, '')   // 制表符
        .replace(/\f/g, '') // 换页符
        .replace(/\n/g, ''); // 新增 - 换行
}
function modeFromNumber(num) {
    switch (num) {
        case 1: return 'rtl';
        case 5: return 'top';
        case 4: return 'bottom';
        default: return 'rtl';
    }
}

function formatComment(comment) {
    const time = comment.time;
    const text = escapeStringForJS(comment.text);
    const mode = comment.mode;
    const fontSize = comment.style.fontSize;
    const color = comment.style.color;
    const textShadow = comment.style.textShadow;
    return `{ time: ${time}, text: '${text}', mode: '${mode}', style: {  fillStyle: '${color}', strokeStyle: '${textShadow}'} }`;
}
function processComments(jsonFilePath, outputDir, callback) {
    fs.readFile(jsonFilePath, 'utf8', (err, data) => {
        if (err) {
            console.error('Failed to read JSON file:', err);
            return callback(err);
        }

        const jsonData = JSON.parse(data);
        const comments = jsonData.comments.map(comment => {
            const [time, mode, color] = comment.p.split(',');
            const colorCSS = convertHexColorToCSS(parseInt(color));
            const textShadow = colorCSS === '#000000'
                ? '#fff'
                : '#000';
            return {
                time: parseFloat(time),
                text: escapeStringForJS(comment.m),
                mode: modeFromNumber(parseInt(mode)),
                style: {
                    fontSize: '30px',
                    color: colorCSS,
                    textShadow: textShadow
                }
            };
        });

        const formattedComments = comments.map(formatComment).join(',\n');
        const template = `danmaku = new Danmaku({\n    container: document.getElementById('danmaku-container'),\n    media: document.getElementById('video-player'),\n    comments: [\n${formattedComments}\n],\ engine: 'canvas'});`;
        const outputFilePath = path.join(outputDir, path.basename(jsonFilePath, '.json') + '.js');
        fs.writeFile(outputFilePath, template, 'utf8', (err) => {
            if (err) {
                console.error('Failed to write JS file:', err);
                return callback(err);
            }
            console.log('JS file saved successfully:', outputFilePath);
            callback(null);
        });
    });
}

module.exports = { processComments };
