module MetadataSourceCrosswalks
  extend ActiveSupport::Concern
  class Kaplan
    def self.mapping(term_to_be_mapped)
      terms = {'ref_1'=>'identifier',
               'ref_2'=>'identifier',
               'genre'=>'item_type',
               'genre_sublevel'=>'item_type',
               'description_1'=>'description',
               'description_2'=>'description',
               'person_name_1'=>'personal_name',
               'person_name_2'=>'personal_name',
               'corporation_name'=>'corporate_name',
               'location'=>'geographic_subject',
               'date'=>'date'
      }
      mapped_term = terms[term_to_be_mapped].present? ? terms[term_to_be_mapped] : nil
      return mapped_term
    end
  end
end