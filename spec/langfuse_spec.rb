# frozen_string_literal: true

RSpec.describe Langfuse do
  it "has a version number" do
    expect(Langfuse::VERSION).not_to be_nil
  end

  describe ".reset!" do
    it "resets configuration and client" do
      described_class.reset!
      expect(described_class.instance_variable_get(:@configuration)).to be_nil
      expect(described_class.instance_variable_get(:@client)).to be_nil
    end
  end

  # These will be enabled when Config and Client are implemented
  # describe ".configure" do
  #   it "yields configuration" do
  #     expect { |b| described_class.configure(&b) }.to yield_with_args(Langfuse::Config)
  #   end
  # end
end
