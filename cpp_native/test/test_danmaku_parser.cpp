// test_danmaku_parser.cpp - DanmakuParser unit tests
// Build: g++ -std=c++20 -Wall -Wextra -Wpedantic -Wno-deprecated-declarations
//        -Wno-class-memaccess -Wno-unused-function -Wno-template-body
//        -I ../modules -I ../third_party/pugixml -I ../third_party/rapidjson/include
//        -o test_danmaku_parser test_danmaku_parser.cpp ../src/danmaku_parser.cpp ../third_party/pugixml/pugixml.cpp

#include <cstdio>
#include <cstring>
#include <string>
#include "danmaku_parser.h"

static int tests_passed = 0;
static int tests_failed = 0;

#define TEST(name) printf("  TEST: %s ... ", name);
#define PASS() do { printf("PASS\n"); tests_passed++; } while(0)
#define FAIL_MSG(msg) do { printf("FAIL: %s\n", msg); tests_failed++; } while(0)
#define REQUIRE(cond, msg) do { if (!(cond)) { FAIL_MSG(msg); return; } } while(0)

void test_parse_xml_basic() {
    TEST("parseXml basic bilibili format");
    const char* xml = R"==(<?xml version="1.0" encoding="UTF-8"?>
    <i><d p="12.3,1,25,16777215,1717000000,0,ABC,0">Hello</d></i>)==";
    auto json = nipaplay::DanmakuParser::parseXmlToJson(xml);
    REQUIRE(json.find("\"t\":12.3") != std::string::npos, "time field missing");
    REQUIRE(json.find("\"c\":\"Hello\"") != std::string::npos, "content field missing");
    REQUIRE(json.find("\"y\":\"scroll\"") != std::string::npos, "type field missing");
    REQUIRE(json.find("\"r\":\"rgb(255,255,255)\"") != std::string::npos, "color field missing");
    REQUIRE(json.find("\"fontSize\":25") != std::string::npos, "fontSize field missing");
    REQUIRE(json.find("\"originalType\":1") != std::string::npos, "originalType field missing");
    REQUIRE(json.find("\"timestamp\":1717000000") != std::string::npos, "timestamp field missing");
    REQUIRE(json.find("\"senderId\":\"ABC\"") != std::string::npos, "senderId field missing");
    REQUIRE(json.find("\"source\":\"bilibili\"") != std::string::npos, "source field missing");
    REQUIRE(json.find("\"count\":1") != std::string::npos, "count field missing");
    PASS();
}

void test_parse_xml_top_bottom() {
    TEST("parseXml top and bottom mode");
    const char* xml = R"==(<i>
    <d p="5.7,5,25,255,0,0,,0">Top danmaku</d>
    <d p="10.0,4,25,65280,0,0,,0">Bottom danmaku</d>
    </i>)==";
    auto json = nipaplay::DanmakuParser::parseXmlToJson(xml);
    REQUIRE(json.find("\"y\":\"top\"") != std::string::npos, "top mode missing");
    REQUIRE(json.find("\"y\":\"bottom\"") != std::string::npos, "bottom mode missing");
    REQUIRE(json.find("\"count\":2") != std::string::npos, "count should be 2");
    PASS();
}

void test_parse_xml_entities() {
    TEST("parseXml with XML entity decoding");
    // Use raw string with delimiter to avoid quote issues
    // The XML contains < and > which should be decoded to < and >
    std::string xml = "<i><d p=\"1.0,1,25,16777215,0,0,,0\">";
    xml += "<tag>";
    xml += "</d></i>";
    auto json = nipaplay::DanmakuParser::parseXmlToJson(xml);
    REQUIRE(json.find("\"c\":\"<tag>\"") != std::string::npos, "entity decode failed");
    PASS();
}

void test_parse_xml_fallback() {
    TEST("parseXml fallback for malformed XML");
    // Missing root <i> node - DOM parse should fail, trigger fallback scanner
    std::string xml = "<d p=\"5.0,5,25,255,0,0,,0\">Top danmaku</d>";
    auto json = nipaplay::DanmakuParser::parseXmlToJson(xml);
    REQUIRE(json.find("\"y\":\"top\"") != std::string::npos, "fallback top mode missing");
    REQUIRE(json.find("\"c\":\"Top danmaku\"") != std::string::npos, "fallback content missing");
    PASS();
}

void test_parse_xml_empty_content_skipped() {
    TEST("parseXml empty content skipped");
    const char* xml = R"==(<i><d p="1.0,1,25,16777215,0,0,,0"></d></i>)==";
    auto json = nipaplay::DanmakuParser::parseXmlToJson(xml);
    REQUIRE(json.find("\"count\":0") != std::string::npos, "empty content should be skipped");
    PASS();
}

void test_parse_xml_missing_p_attr() {
    TEST("parseXml missing p attribute skipped");
    const char* xml = R"==(<i><d>Hello</d><d p="1.0,1,25,16777215,0,0,,0">Valid</d></i>)==";
    auto json = nipaplay::DanmakuParser::parseXmlToJson(xml);
    REQUIRE(json.find("\"count\":1") != std::string::npos, "only valid danmaku should count");
    PASS();
}

void test_parse_json_basic() {
    TEST("parseJson basic standardization (t/c/y/r source)");
    // Build JSON manually to avoid quote escaping issues
    std::string json_in = R"==([{"t":5.5,"c":"test","y":"top","r":"rgb(255,0,0)"}])==";
    auto json_out = nipaplay::DanmakuParser::parseJsonToStandardized(json_in);
    REQUIRE(json_out.find("\"time\":5.5") != std::string::npos, "time field missing");
    REQUIRE(json_out.find("\"content\":\"test\"") != std::string::npos, "content field missing");
    REQUIRE(json_out.find("\"type\":\"top\"") != std::string::npos, "type field missing");
    REQUIRE(json_out.find("\"color\":\"rgb(255,0,0)\"") != std::string::npos, "color field missing");
    REQUIRE(json_out.find("\"count\":1") != std::string::npos, "count missing");
    PASS();
}

void test_parse_json_dual_source() {
    TEST("parseJson dual source mapping (time/content/type/color source)");
    // Test with dandanplay API format (time/content/type/color)
    std::string json_in = R"==([{"time":3.0,"content":"hello","type":"scroll","color":"rgb(0,0,255)"}])==";
    auto json_out = nipaplay::DanmakuParser::parseJsonToStandardized(json_in);
    REQUIRE(json_out.find("\"time\":3.0") != std::string::npos, "time from 'time' field missing");
    REQUIRE(json_out.find("\"content\":\"hello\"") != std::string::npos, "content from 'content' field missing");
    REQUIRE(json_out.find("\"type\":\"scroll\"") != std::string::npos, "type from 'type' field missing");
    REQUIRE(json_out.find("\"color\":\"rgb(0,0,255)\"") != std::string::npos, "color from 'color' field missing");
    PASS();
}

void test_parse_json_preserve_extra_fields() {
    TEST("parseJson preserves extra fields (fontSize, originalType)");
    std::string json_in = R"==([{"t":1.0,"c":"test","y":"scroll","r":"rgb(255,255,255)","fontSize":30,"originalType":6}])==";
    auto json_out = nipaplay::DanmakuParser::parseJsonToStandardized(json_in);
    REQUIRE(json_out.find("\"fontSize\":30") != std::string::npos, "fontSize should be preserved");
    REQUIRE(json_out.find("\"originalType\":6") != std::string::npos, "originalType should be preserved");
    PASS();
}

void test_parse_json_invalid_input() {
    TEST("parseJson invalid input returns empty");
    auto json_out = nipaplay::DanmakuParser::parseJsonToStandardized("not json");
    REQUIRE(json_out.find("\"count\":0") != std::string::npos, "invalid json should return count 0");
    PASS();
}

void test_parse_json_numeric_type() {
    TEST("parseJson numeric type field conversion");
    // type=1 should be converted to "top" (0=scroll, 1=top, 2=bottom)
    std::string json_in = R"==([{"time":1.0,"content":"test","type":1,"color":"rgb(255,255,255)"}])==";
    auto json_out = nipaplay::DanmakuParser::parseJsonToStandardized(json_in);
    REQUIRE(json_out.find("\"type\":\"top\"") != std::string::npos, "numeric type 1 should be top");
    PASS();
}

void test_color_to_rgb() {
    TEST("colorToRgb conversion");
    auto result1 = nipaplay::DanmakuParser::colorToRgb(16777215);
    REQUIRE(result1 == "rgb(255,255,255)", "0xFFFFFF should be rgb(255,255,255)");
    auto result2 = nipaplay::DanmakuParser::colorToRgb(255);
    REQUIRE(result2 == "rgb(0,0,255)", "0x0000FF should be rgb(0,0,255)");
    auto result3 = nipaplay::DanmakuParser::colorToRgb(65280);
    REQUIRE(result3 == "rgb(0,255,0)", "0x00FF00 should be rgb(0,255,0)");
    PASS();
}

void test_mode_to_type() {
    TEST("modeToType mapping");
    REQUIRE(std::strcmp(nipaplay::DanmakuParser::modeToType(1), "scroll") == 0, "mode 1 = scroll");
    REQUIRE(std::strcmp(nipaplay::DanmakuParser::modeToType(4), "bottom") == 0, "mode 4 = bottom");
    REQUIRE(std::strcmp(nipaplay::DanmakuParser::modeToType(5), "top") == 0, "mode 5 = top");
    REQUIRE(std::strcmp(nipaplay::DanmakuParser::modeToType(6), "scroll") == 0, "mode 6 = scroll (reverse)");
    REQUIRE(std::strcmp(nipaplay::DanmakuParser::modeToType(7), "scroll") == 0, "mode 7 = scroll (default)");
    PASS();
}

void test_parse_xml_weight_field() {
    TEST("parseXml optional weight field (9th p attribute)");
    const char* xml = R"==(<i><d p="1.0,1,25,16777215,0,0,ABC,0,10">Weighted</d></i>)==";
    auto json = nipaplay::DanmakuParser::parseXmlToJson(xml);
    REQUIRE(json.find("\"c\":\"Weighted\"") != std::string::npos, "weight field danmaku should parse");
    REQUIRE(json.find("\"count\":1") != std::string::npos, "count should be 1");
    PASS();
}

int main() {
    printf("=== DanmakuParser Unit Tests ===\n\n");

    test_parse_xml_basic();
    test_parse_xml_top_bottom();
    test_parse_xml_entities();
    test_parse_xml_fallback();
    test_parse_xml_empty_content_skipped();
    test_parse_xml_missing_p_attr();
    test_parse_json_basic();
    test_parse_json_dual_source();
    test_parse_json_preserve_extra_fields();
    test_parse_json_invalid_input();
    test_parse_json_numeric_type();
    test_color_to_rgb();
    test_mode_to_type();
    test_parse_xml_weight_field();

    printf("\n=== Results: %d passed, %d failed ===\n", tests_passed, tests_failed);
    return tests_failed > 0 ? 1 : 0;
}
