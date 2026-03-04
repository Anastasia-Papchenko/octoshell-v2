class AddTimestampsToCorePartitions < ActiveRecord::Migration[8.0]
  def change
    add_timestamps :core_partitions, null: true
  end
end
