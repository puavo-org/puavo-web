class SchoolGroupRef < ActiveRecord::Base
  belongs_to :school
  belongs_to :group
end
