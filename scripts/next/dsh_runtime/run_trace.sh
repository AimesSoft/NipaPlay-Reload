#!/bin/zsh
# The tool sequence the trace drives: see trace.py.
export TRACE_COMPACT=1
export TRACE_SCRIPT='[{"tool":"bash","args":{"description":"d","command":"echo hi; ls"}},{"tool":"bash","args":{"description":"bg","command":"sleep 1; echo bg","run_in_background":true}},{"tool":"job_list","args":{}},{"tool":"read","args":{"file_path":"AGENTS.md"}},{"tool":"read_image","args":{"file_path":"pic.png"}},{"tool":"write","args":{"file_path":"out.txt","content":"x"}},{"tool":"job_output","args":{"job_id":"JOBID","wait":true,"timeout_ms":3000}},{"tool":"web_fetch","args":{"url":"https://example.com/"}},{"tool":"todo_write","args":{"todos":[{"content":"a","status":"pending"}]}},{"tool":"list_agents","args":{}},{"tool":"subagent","args":{"description":"sub","prompt":"say hi"}},{"text":true},{"text":true}]'
exec python3 "${0:A:h}/trace.py"
