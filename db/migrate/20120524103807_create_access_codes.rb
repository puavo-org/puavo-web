class CreateAccessCodes < ActiveRecord::Migration
  def self.up
    create_table :access_codes do |t|
      t.string :access_code
      t.string :client_id
      t.string :user_dn

      t.timestamps
    end
  end

  def self.down
    drop_table :access_codes
  end
end
