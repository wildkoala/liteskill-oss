# ReqLLM's validate_model/1 checks AWS credentials via env vars before
# the request reaches Req.Test plugs. Set a dummy token so Bedrock
# embedding tests pass on CI where no real AWS env vars exist.
System.put_env("AWS_BEARER_TOKEN_BEDROCK", "test-token-for-reqllm-validation")

ExUnit.start(capture_log: true)

# Suppress Postgrex disconnect errors that leak to stderr when tests kill
# processes holding shared sandbox connections (e.g. Runner timeout tests).
# These logs come from the Postgrex.Protocol pool process which is outside
# the test process tree, so ExUnit's capture_log cannot associate them.
Logger.put_module_level(Postgrex.Protocol, :none)

Ecto.Adapters.SQL.Sandbox.mode(Liteskill.Repo, :manual)
