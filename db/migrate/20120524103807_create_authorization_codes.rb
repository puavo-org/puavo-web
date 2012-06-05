class CreateAuthorizationCodes < ActiveRecord::Migration
  def self.up
    create_table :authorization_codes do |t|
      t.string :code
      t.string :client_id
      t.string :user_dn
      t.string :redirect_uri

      t.timestamps
    end
  end

  def self.down
    drop_table :authorization_codes
  end
end
