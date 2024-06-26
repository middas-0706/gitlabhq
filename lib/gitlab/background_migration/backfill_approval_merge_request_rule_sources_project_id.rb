# frozen_string_literal: true

module Gitlab
  module BackgroundMigration
    # rubocop: disable Migration/BackgroundMigrationBaseClass -- BackfillDesiredShardingKeyJob inherits from BatchedMigrationJob.
    class BackfillApprovalMergeRequestRuleSourcesProjectId < BackfillDesiredShardingKeyJob
      operation_name :backfill_approval_merge_request_rule_sources_project_id
      feature_category :code_review_workflow
    end
    # rubocop: enable Migration/BackgroundMigrationBaseClass
  end
end
