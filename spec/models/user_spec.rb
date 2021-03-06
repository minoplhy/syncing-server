require 'rails_helper'

RSpec.describe User, type: :model do
  subject do
    described_class.create(
      pw_nonce: 'somenonce',
      version: '004',
      email: 'sn@testing.com',
      encrypted_password: 'encrypted',
      kp_origination: 'registration',
      kp_created: DateTime.now.to_i,
      pw_salt: 'salt',
      pw_cost: 1,
      pw_alg: 'alg',
      pw_func: 'func',
      pw_key_size: 1
    )
  end

  describe 'serializable_hash' do
    let(:hash) do
      subject.serializable_hash
    end

    let(:hash_keys) do
      %w[uuid email].sort
    end

    specify do
      expect(hash.count).to eq 2
      expect(hash.keys.sort).to contain_exactly(*hash_keys)
    end
  end

  describe 'auth_params' do
    specify do
      auth_params = subject.key_params
      expect(auth_params.keys.sort).to contain_exactly(:identifier, :pw_nonce, :version)
    end

    specify do
      auth_params = subject.key_params(true)
      expect(auth_params.keys.sort).to contain_exactly(:identifier, :created, :origination, :pw_nonce, :version)
    end

    specify do
      subject.version = '003'

      auth_params = subject.key_params
      expect(auth_params.keys.sort).to contain_exactly(:identifier, :pw_nonce, :version, :pw_cost)
    end

    specify do
      subject.version = '002'

      auth_params = subject.key_params
      expect(auth_params.keys.sort).to contain_exactly(:email, :identifier, :pw_cost, :pw_salt, :version)
    end

    specify do
      subject.version = '001'

      auth_params = subject.key_params
      expect(auth_params.keys.sort).to contain_exactly(:email, :identifier, :pw_alg, :pw_cost, :pw_func, :pw_key_size, :pw_salt, :version)
    end
  end

  describe 'bytes_to_megabytes' do
    specify do
      expect(subject.bytes_to_megabytes(1_000_000)).to eq '0.95MB'
    end
  end

  describe 'total_data_size' do
    specify do
      content = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque euismod'\
       ' nulla iaculis lacus consectetur, nec feugiat libero pellentesque. Vestibulum tincidunt'\
       ' tempor accumsan. Phasellus sed imperdiet libero. Proin ultrices vehicula nulla, vitae cras amet.'

      (1..256).each do |_i|
        item = Item.new(user_uuid: subject.uuid, content: content)
        item.save
      end

      expect(subject.total_data_size).to eq('0.06MB')
    end
  end

  describe 'items_by_size' do
    specify do
      item_contents = []

      item_contents << 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Curabitur sollicitudin'\
       ' rutrum diam non rutrum. Aliquam eu malesuada nunc, et tincidunt dolor. Sed blandit odio vitae'\
       ' lorem tristique luctus. Donec faucibus quam vitae porta tincidunt. Morbi dolor eros, egestas eget'\
       ' magna eget, volutpat maximus ipsum. Nulla semper dolor dignissim massa molestie egestas. Aenean'\
       ' dignissim suscipit iaculis. Vestibulum euismod accumsan consequat. Quisque quis dictum eros, sed'\
       ' vestibulum enim. Etiam ultricies blandit metus.'

      item_contents << 'Lorem ipsum dolor sit amet, consectetur adipiscing elit.'\
       ' Phasellus rutrum vitae magna et blandit. Ut id urna a lorem massa nunc.'

      item_contents << 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque euismod'\
       ' nulla iaculis lacus consectetur, nec feugiat libero pellentesque. Vestibulum tincidunt'\
       ' tempor accumsan. Phasellus sed imperdiet libero. Proin ultrices vehicula nulla, vitae cras amet.'

      items = []

      item_contents.each_with_index do |content, index|
        item = Item.create(user_uuid: subject.uuid, content: content)
        items[index] = { content: content, uuid: item.uuid }
      end

      items_by_size = subject.items_by_size

      expect(items_by_size[0][:uuid]).to eq(items[0][:uuid])
      expect(items_by_size[1][:uuid]).to eq(items[2][:uuid])
      expect(items_by_size[2][:uuid]).to eq(items[1][:uuid])
    end
  end

  describe 'download_backup' do
    specify do
      content = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque euismod'\
       ' nulla iaculis lacus consectetur, nec feugiat libero pellentesque. Vestibulum tincidunt'\
       ' tempor accumsan. Phasellus sed imperdiet libero. Proin ultrices vehicula nulla, vitae cras amet.'

      Item.create(user_uuid: subject.uuid, content: content)

      subject.download_backup

      expect(File).to exist("tmp/#{subject.email}-restore.txt")
    end
  end

  describe 'disable_mfa' do
    context 'when allowEmailRecovery is false' do
      it 'MFA item should not be marked as deleted' do
        data = { allowEmailRecovery: false }
        content = "002#{Base64.encode64(JSON.dump(data))}"

        item = Item.create(user_uuid: subject.uuid, content: content, content_type: 'SF|MFA')

        subject.disable_mfa

        item.reload
        expect(item.deleted).to be false
      end
    end

    context 'when allowEmailRecovery is true' do
      it 'MFA item should be marked as deleted' do
        data = { allowEmailRecovery: true }
        content = "002#{Base64.encode64(JSON.dump(data))}"

        item = Item.create(user_uuid: subject.uuid, content: content, content_type: 'SF|MFA')

        subject.disable_mfa

        item.reload
        expect(item.deleted).to be true
      end
    end
  end

  describe 'compute_data_signature' do
    specify do
      content = 'Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque euismod'\
      ' nulla iaculis lacus consectetur, nec feugiat libero pellentesque. Vestibulum tincidunt'\
      ' tempor accumsan. Phasellus sed imperdiet libero. Proin ultrices vehicula nulla, vitae cras amet.'

      Item.create(user_uuid: subject.uuid, content: content, content_type: 'Note')
      hash = subject.compute_data_signature

      expect(hash).to_not be_nil
    end
  end

  describe 'disable_email_backups' do
    specify do
      data = { subtype: 'backup.email_archive' }
      item_content = "002#{Base64.encode64(JSON.dump(data))}"
      Item.create(user_uuid: subject[:uuid], content: item_content, content_type: 'SF|Extension')

      extension_item = subject.items.where(content_type: 'SF|Extension', deleted: false).first
      subject.disable_email_backups

      extension_item.reload
      expect(extension_item.deleted).to be true
    end
  end
end
