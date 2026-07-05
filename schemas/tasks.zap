package tasks

# Conformed from hanzoai/tasks/schema/tasks.zap (the hand-sketch) to canonical
# zapgen grammar. This is the demonstration source of truth for zap-proto/gen.
# Offsets are author-controlled and append-only; method ordinals auto-assign by
# declaration order. Generate: bin/zapsdk <lang> schemas/tasks.zap

# @openapi:version 1.0.0
# @openapi:server  https://api.hanzo.ai/v1

struct WorkflowExecution {
  workflowId text @0
  runId      text @8
}

struct WorkflowType {
  name text @0
}

struct StartWorkflowRequest {
  namespace  text  @0
  workflowId text  @8
  taskQueue  text  @16
  input      bytes @24
}

struct StartWorkflowResponse {
  runId text @0
}

struct SignalWorkflowRequest {
  namespace  text  @0
  workflowId text  @8
  runId      text  @16
  signalName text  @24
  input      bytes @32
}

struct DescribeWorkflowRequest {
  namespace  text @0
  workflowId text @8
  runId      text @16
}

struct WorkflowExecutionInfo {
  execution     WorkflowExecution @0
  type          WorkflowType      @4
  startTimeMs   i64               @8
  closeTimeMs   i64               @16
  status        u8                @24
  historyLength i64               @32
}

struct DescribeWorkflowResponse {
  info WorkflowExecutionInfo @0
}

struct HealthResponse {
  service text @0
  status  text @8
}

interface Tasks {
  startWorkflow(req: StartWorkflowRequest) returns (resp: StartWorkflowResponse)
  signalWorkflow(req: SignalWorkflowRequest)
  describeWorkflow(req: DescribeWorkflowRequest) returns (resp: DescribeWorkflowResponse)
  health() returns (resp: HealthResponse)
}
