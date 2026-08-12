class BackfillAndRequireUserRole < ActiveRecord::Migration[8.1]
  def up
    # role has been a free-text column with no default and no enforcement, so a
    # nil role was possible and meant nothing in particular. Settle it on the
    # least-privileged value before making it required.
    execute "UPDATE users SET role = 'member' WHERE role IS NULL OR role = ''"

    change_column_default :users, :role, from: nil, to: "member"
    change_column_null :users, :role, false
  end

  def down
    change_column_null :users, :role, true
    change_column_default :users, :role, from: "member", to: nil
  end
end
