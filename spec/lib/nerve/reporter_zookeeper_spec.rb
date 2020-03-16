require 'spec_helper'
require 'nerve/reporter/zookeeper'
require 'zookeeper'

describe Nerve::Reporter::Zookeeper do
  let(:base_config) { {
      'zk_hosts' => ['zkhost1', 'zkhost2'],
      'zk_path' => 'zk_path',
      'instance_id' => 'instance_id',
      'host' => 'host',
      'port' => 'port'
    }
  }

  let(:config) { base_config }

  subject { Nerve::Reporter::Zookeeper.new(config) }

  let(:zk) { double("zk") }

  before :each do
    Nerve::Reporter::Zookeeper.class_variable_set(:@@zk_pool, {})

    pool_count = {}
    allow(pool_count).to receive(:[]).and_return(1)
    Nerve::Reporter::Zookeeper.class_variable_set(:@@zk_pool_count, pool_count)
  end

  it 'actually constructs an instance' do
    expect(subject.is_a?(Nerve::Reporter::Zookeeper)).to eql(true)
  end

  it 'deregisters service on exit' do
    allow(zk).to receive(:close!)
    allow(zk).to receive(:connected?).and_return(true)
    expect(zk).to receive(:exists?) { "zk_path" }.and_return(false)
    expect(zk).to receive(:mkdir_p) { "zk_path" }
    expect(zk).to receive(:create) { "full_path" }
    expect(zk).to receive(:delete).with("full_path", anything())

    allow(ZK).to receive(:new).and_return(zk)

    reporter = Nerve::Reporter::Zookeeper.new(config)
    reporter.start
    reporter.report_up
    reporter.stop
  end

  context "when reporter is up" do
    before(:each) do
      allow(zk).to receive(:close!)
      allow(zk).to receive(:connected?).and_return(true)
      allow(zk).to receive(:exists?) { "zk_path" }.and_return(false)
      allow(zk).to receive(:mkdir_p) { "zk_path" }
      allow(zk).to receive(:create) { "full_path" }
      allow(zk).to receive(:set) { "full_path" }
      allow(zk).to receive(:delete).with("full_path", anything())
      allow(ZK).to receive(:new).and_return(zk)
      @reporter = Nerve::Reporter::Zookeeper.new(config)
      @reporter.start
    end

    after(:each) do
      # reset the class variable to avoid mock object zk leak
      Nerve::Reporter::Zookeeper.class_variable_set(:@@zk_pool, {})
      Nerve::Reporter::Zookeeper.class_variable_set(:@@zk_pool_count, {})
    end

    it "returns true on report_up" do
      expect(@reporter.report_up).to be true
    end

    it "returns true on report_down" do
      @reporter.report_up
      expect(@reporter.report_down).to be true
    end

    it "returns true on ping?" do
      @reporter.report_up

      stat = double("zk_stat")
      allow(stat).to receive(:exists?).and_return(true)
      expect(zk).to receive(:stat) { "zk_path" }.and_return(stat)
      expect(@reporter.ping?).to be true
    end

    context "when zk.connected? started to return false" do
      before(:each) do
        @reporter.report_up
        # this condition is triggered if connection has been lost for a while (a few sec)
        expect(zk).to receive(:connected?).and_return(false)
      end

      it 'returns false on ping?' do
        expect(zk).not_to receive(:stat)
        expect(@reporter.ping?).to be false
      end

      it 'returns false on report_up without zk operation' do
        expect(zk).not_to receive(:set)
        expect(@reporter.report_up).to be false
      end

      it 'returns false on report_up without zk operation' do
        expect(zk).not_to receive(:delete)
        expect(@reporter.report_down).to be false
      end
    end

    context "when there is a short disconnection" do
      before(:each) do
        @reporter.report_up
      end

      it 'returns false on ping?' do
        # this condition is triggered if connection is shortly interrupted
        # so connected? still return true
        expect(zk).to receive(:stat).and_raise(ZK::Exceptions::OperationTimeOut)
        expect(@reporter.ping?).to be false
      end

      it 'swallows zk connection errors and returns false on report_up' do
        # this condition is triggered if connection is shortly interrupted
        # so connected? still return true
        expect(zk).to receive(:set).and_raise(ZK::Exceptions::OperationTimeOut)
        expect(@reporter.report_up).to be false
      end

      it 'swallows zk connection errors and returns false on report_down' do
        # this condition is triggered if connection is shortly interrupted
        # so connected? still return true
        expect(zk).to receive(:delete).and_raise(ZK::Exceptions::OperationTimeOut)
        expect(@reporter.report_down).to be false
      end

      it 'swallows zookeeper not connected errors and returns false on report_up' do
        # this condition is triggered if connection is shortly interrupted
        # so connected? still return true
        expect(zk).to receive(:set).and_raise(::Zookeeper::Exceptions::NotConnected)
        expect(@reporter.report_up).to be false
      end

      it 'swallows zookeeper not connected errors and returns false on report_down' do
        # this condition is triggered if connection is shortly interrupted
        # so connected? still return true
        expect(zk).to receive(:delete).and_raise(::Zookeeper::Exceptions::NotConnected)
        expect(@reporter.report_down).to be false
      end

    end

    context "when there is other ZK errors" do
      before(:each) do
        @reporter.report_up
      end

      it 'raises zk non-connection error on ping?' do
        # this condition is triggered if connection is shortly interrupted
        # so connected? still return true
        expect(zk).to receive(:stat).and_raise(ZK::Exceptions::SessionExpired)
        expect {@reporter.ping?}.to raise_error(ZK::Exceptions::SessionExpired)
      end

      it 'raises zk non-connetion errors on report_up' do
        # this condition is triggered if connection is shortly interrupted
        # so connected? still return true
        expect(zk).to receive(:set).and_raise(ZK::Exceptions::SessionExpired)
        expect {@reporter.report_up}.to raise_error(ZK::Exceptions::SessionExpired)
      end

      it 'raises zk non-connetion errors on report_down' do
        # this condition is triggered if connection is shortly interrupted
        # so connected? still return true
        expect(zk).to receive(:delete).and_raise(ZK::Exceptions::SessionExpired)
        expect {@reporter.report_down}.to raise_error(ZK::Exceptions::SessionExpired)
      end
    end

    context "when reporter up with setting ZK node type" do

      it 'ZK client should use the default node type as :ephemeral_sequential if not specified' do
        expect(zk).to receive(:create).with(anything, {:data => "{\"host\":\"host\",\"port\":\"port\",\"name\":\"instance_id\"}", :mode => :ephemeral_sequential})
        expect(@reporter.report_up).to be true
      end

      it 'ZK client should use the node type as specified' do
        @reporter.instance_variable_set(:@mode, :persistent)

        expect(zk).to receive(:create).with(anything, {:data => "{\"host\":\"host\",\"port\":\"port\",\"name\":\"instance_id\"}", :mode => :persistent})
        expect(@reporter.report_up).to be true

        @reporter.instance_variable_set(:@mode, nil)
      end
    end
  end

  context "reporter path encoding" do
    it 'encode child name with optional fields' do
      service = {
        'instance_id' => 'i-xxxxxx',
        'host' => '127.0.0.1',
        'port' => 3000,
        'labels' => {
          'region' => 'us-east-1',
          'az' => 'us-east-1a'
        },
        'zk_hosts' => ['zkhost1', 'zkhost2'],
        'zk_path' => 'zk_path',
        'use_path_encoding' => true,
      }
      expected = {
        'name' => 'i-xxxxxx',
        'host' => '127.0.0.1',
        'port' => 3000,
        'labels' => {
          'region' => 'us-east-1',
          'az' => 'us-east-1a'
        }
      }
      reporter = Nerve::Reporter::Zookeeper.new(service)
      str = reporter.send(:encode_child_name, service)
      JSON.parse(Base64.urlsafe_decode64(str[12...-1])).should == expected
    end

    it 'encode child name with required fields only' do
      service = {
        'instance_id' => 'i-xxxxxx',
        'use_path_encoding' => true,
        'host' => '127.0.0.1',
        'port' => 3000,
        'zk_hosts' => ['zkhost1', 'zkhost2'],
        'zk_path' => 'zk_path',
        'use_path_encoding' => true,
      }
      expected = {
        'name' => 'i-xxxxxx',
        'host' => '127.0.0.1',
        'port' => 3000
      }
      reporter = Nerve::Reporter::Zookeeper.new(service)
      str = reporter.send(:encode_child_name, service)
      JSON.parse(Base64.urlsafe_decode64(str[11...-1])).should == expected
    end

    it 'encode child name without path encoding' do
      service = {
        'instance_id' => 'i-xxxxxx',
        'host' => '127.0.0.1',
        'port' => 3000,
        'zk_hosts' => ['zkhost1', 'zkhost2'],
        'zk_path' => 'zk_path',
      }
      reporter = Nerve::Reporter::Zookeeper.new(service)
      expect(reporter.send(:encode_child_name, service)).to eq('/i-xxxxxx_')
    end
  end

  context 'parse node type properly when reporter is initializing' do
    it 'node type should be converted to symbol' do
      service = config.merge({'node_type' => 'ephemeral'})
      reporter = Nerve::Reporter::Zookeeper.new(service)
      expect(reporter.instance_variable_get(:@mode)).to be_kind_of(Symbol)
      expect(reporter.instance_variable_get(:@mode)).to eq(:ephemeral)
    end

    it 'default type of node is :ephemeral_sequential' do
      reporter = Nerve::Reporter::Zookeeper.new(config)
      expect(reporter.instance_variable_get(:@mode)).to eq(:ephemeral_sequential)
    end
  end

  describe '#ping?' do
    let(:path) { '/test/path' }
    let(:data) { {'host' => 'i-test', 'test' => true} }
    let(:node_type) { 'persistent' }
    let(:zk_connected) { true }
    let(:node_exists) { true }
    let(:node_mtime) { nil }
    let(:stat) {
      data = {'exists' => node_exists}

      if node_exists
        ephemeralOwner = 1 if node_type.start_with?('ephemeral')
        data.merge!({'mtime' => node_mtime.to_i * 1000,
                    'ephemeralOwner' => ephemeralOwner})
      end

      Zookeeper::Stat.new(data)
    }

    before :each do
      subject.instance_variable_set(:@zk, zk)
      subject.instance_variable_set(:@data, data)
      subject.instance_variable_set(:@full_key, path) if node_exists
      allow(zk).to receive(:stat).and_return(stat)
      allow(zk).to receive(:connected?).and_return(zk_connected)
    end

    it 'calls stat on zookeeper' do
      expect(zk).to receive(:stat).exactly(:once)
      subject.ping?
    end

    context 'when zk stat returns false' do
      let(:node_exists) { false }

      it 'returns false' do
        expect(subject.ping?).to eq(false)
      end
    end

    context 'when zk stat returns true' do
      let(:node_exists) { true }

      it 'returns true' do
        expect(subject.ping?).to eq(true)
      end
    end

    it 'does not call renew_ttl' do
      expect(subject).not_to receive(:renew_ttl)
      subject.ping?
    end

    context 'with ttl set' do
      let(:config) {
        base_config.merge({'ttl_duration' => ttl,
                           'node_type' => node_type})
      }
      let(:ttl) { 360 }
      let(:mtime) { Time.now if node_exists }

      it 'calls renew_ttl' do
        expect(subject).to receive(:renew_ttl).with(stat).exactly(:once)
        subject.ping?
      end

      context 'when node does not exist' do
        let(:node_exists) { false }

        it 'calls renew_ttl' do
          allow(zk).to receive(:exists?).with(path).and_return(true)
          expect(subject).to receive(:renew_ttl).with(stat).exactly(:once)
          subject.ping?
        end
      end
    end

    context 'when disconnected from zookeeper' do
      let(:zk_connected) { false }

      it 'returns false' do
        expect(subject.ping?).to be(false)
      end
    end
  end

  describe '#renew_ttl' do
    let(:config) {
      base_config.merge({'zk_path' => parent_path,
                         'ttl_duration' => ttl,
                         'node_type' => node_type})
    }
    let(:ttl) { 360 }
    let(:parent_path) { '/test' }
    let(:path) { "#{parent_path}/child" }
    let(:data) { {'host' => 'i-test', 'test' => true} }

    let(:node_type) { 'persistent' }
    let(:node_exists) { true }
    let(:node_mtime) { Time.now }
    let(:stat) {
      data = {'exists' => node_exists}

      if node_exists
        ephemeralOwner = 1 if node_type.start_with?('ephemeral')
        data.merge!({'mtime' => node_mtime.to_i * 1000,
                    'ephemeralOwner' => ephemeralOwner})
      end

      Zookeeper::Stat.new(data)
    }

    before :each do
      subject.instance_variable_set(:@zk, zk)
      subject.instance_variable_set(:@full_key, path)
      subject.instance_variable_set(:@key_prefix, path)
      subject.instance_variable_set(:@data, data)
      allow(zk).to receive(:connected?).and_return(true)
      allow(zk).to receive(:exists?).with(parent_path).and_return(true)
    end

    context 'when last TTL has expired' do
      let(:node_mtime) { Time.now - ttl - 1 }

      it 'calls zk_save' do
        expect(subject).to receive(:zk_save).exactly(:once).with(true)
        subject.send(:renew_ttl, stat)
      end

      context 'when node exists' do
        it 'touches the node without changing the data' do
          expect(zk).to receive(:set).with(path, data).exactly(:once)
          subject.send(:renew_ttl, stat)
        end

        it 'does not create a new node' do
          allow(zk).to receive(:set).exactly(:once)
          expect(zk).not_to receive(:create)
          subject.send(:renew_ttl, stat)
        end
      end

      context 'when node does not exist' do
        let(:node_exists) { false }
        let(:node_mtime) { nil }

        it 'creates a new node' do
          existing_mode = subject.instance_variable_get(:@mode)
          expect(zk)
            .to receive(:create)
            .with(path, :data => data, :mode => existing_mode)
            .exactly(:once)

          subject.send(:renew_ttl, stat)
        end
      end

      context 'when writing ephemeral nodes' do
        let(:node_type) { 'ephemeral_sequential' }

        it 'does not call zk_save' do
          expect(subject).not_to receive(:zk_save)
          expect(zk).not_to receive(:create)
          expect(zk).not_to receive(:set)
          subject.send(:renew_ttl, stat)
        end
      end
    end

    context 'when TTL is still active' do
      let(:node_mtime) { Time.now }

      context 'when node exists' do
        it 'does not touch the node' do
          expect(zk).not_to receive(:set)
          expect(zk).not_to receive(:exists?)
          subject.send(:renew_ttl, stat)
        end

        it 'does not create a new node' do
          expect(zk).not_to receive(:create)
          expect(zk).not_to receive(:exists?)
          subject.send(:renew_ttl, stat)
        end
      end
    end

    context 'with TTL disabled' do
      let(:config) { base_config }
      let(:node_mtime) { nil }

      it 'does not raise an error' do
        expect { subject.send(:renew_ttl, stat) }.not_to raise_error
      end

      context 'when ttl is expired' do
        let(:node_mtime) { Time.now - ttl - 1 }

        it 'does not call zk_save' do
          expect(subject).not_to receive(:zk_save)
          expect(zk).not_to receive(:create)
          expect(zk).not_to receive(:set)
          subject.send(:renew_ttl, stat)
        end
      end
    end
  end
end

