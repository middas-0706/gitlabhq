# frozen_string_literal: true

require 'spec_helper'

RSpec.describe BulkImports::Projects::Transformers::ProjectAttributesTransformer, feature_category: :importers do
  describe '#transform' do
    let_it_be(:user) { create(:user) }
    let_it_be(:project) { create(:project, name: 'My Source Project') }
    let_it_be(:bulk_import) { create(:bulk_import, user: user) }

    let(:entity) do
      create(
        :bulk_import_entity,
        source_type: :project_entity,
        bulk_import: bulk_import,
        source_full_path: 'source/full/path',
        destination_slug: 'Destination-Project-Name',
        destination_namespace: destination_namespace
      )
    end

    let(:destination_group) { create(:group) }
    let(:destination_namespace) { destination_group.full_path }
    let(:tracker) { create(:bulk_import_tracker, entity: entity) }
    let(:context) { BulkImports::Pipeline::Context.new(tracker) }
    let(:data) do
      {
        'visibility' => 'private',
        'created_at' => '2016-11-18T09:29:42.634Z'
      }
    end

    subject(:transformed_data) { described_class.new.transform(context, data) }

    it 'transforms name to destination slug' do
      expect(transformed_data[:name]).to eq(entity.destination_slug)
    end

    it 'adds path as normalized name' do
      expect(transformed_data[:path]).to eq(entity.destination_slug.downcase)
    end

    it 'adds import type' do
      expect(transformed_data[:import_type]).to eq(described_class::PROJECT_IMPORT_TYPE)
    end

    describe 'namespace_id' do
      context 'when destination namespace is present' do
        it 'adds namespace_id' do
          expect(transformed_data[:namespace_id]).to eq(destination_group.id)
        end
      end

      context 'when destination namespace is blank' do
        it 'does not add namespace_id key' do
          entity = create(
            :bulk_import_entity,
            source_type: :project_entity,
            bulk_import: bulk_import,
            source_full_path: 'source/full/path',
            destination_slug: 'Destination-Project-Name',
            destination_namespace: ''
          )

          context = double(entity: entity)

          expect(described_class.new.transform(context, data)).not_to have_key(:namespace_id)
        end
      end
    end

    context 'when data has extra keys' do
      it 'returns a fixed number of keys' do
        data = {
          'visibility' => 'private',
          'created_at' => '2016-11-18T09:29:42.634Z',
          'my_key' => 'my_key',
          'another_key' => 'another_key',
          'last_key' => 'last_key'
        }

        transformed_data = described_class.new.transform(context, data)

        expect(transformed_data.keys)
          .to contain_exactly('created_at', 'import_type', 'name', 'namespace_id', 'path', 'visibility_level')
      end
    end

    context 'when destination_slug has invalid characters' do
      let(:entity) do
        create(
          :bulk_import_entity,
          source_type: :project_entity,
          bulk_import: bulk_import,
          source_full_path: 'source/full/path',
          destination_slug: '------------Destination_-Project-_Name------------',
          destination_namespace: destination_namespace
        )
      end

      it 'parameterizes the path' do
        expect(transformed_data[:path]).to eq('destination-project-name')
      end
    end

    context 'when destination namespace already has a group or project with the same name' do
      before do
        create(:project, group: destination_group, name: 'Destination-Project-Name', path: 'project')
        create(:project, group: destination_group, name: 'Destination-Project-Name_1', path: 'project_1')
      end

      it 'makes the name unique by appending a counter' do
        transformed_data = described_class.new.transform(context, data)
        expect(transformed_data['name']).to eq('Destination-Project-Name_2')
      end
    end

    context 'when destination namespace already has a project with the same path' do
      let(:entity) do
        create(
          :bulk_import_entity,
          source_type: :project_entity,
          bulk_import: bulk_import,
          source_full_path: 'source/full/path',
          destination_slug: 'destination-slug-path',
          destination_namespace: destination_namespace
        )
      end

      before do
        create(:project, group: destination_group, name: 'Source Project Name', path: 'destination-slug-path')
        create(:project, group: destination_group, name: 'Source Project Name_1', path: 'destination-slug-path_1')
      end

      it 'makes the path unique by appending a counter' do
        transformed_data = described_class.new.transform(context, data)
        expect(transformed_data['path']).to eq('destination-slug-path_2')
      end
    end

    describe 'visibility level' do
      include_examples 'visibility level settings'
    end
  end
end
