require "./spec_helper"

describe Asterisk::Ami do
  it "decode event" do
    raw = %(Event: Newchannel
Privilege: call,all
Channel: PJSIP/misspiggy-00000001
Uniqueid: 1368479157.3
ChannelState: 3
ChannelStateDesc: Up
CallerIDNum: 657-5309
CallerIDName: Miss Piggy
ConnectedLineName:
ConnectedLineNum:
AccountCode: Pork
Priority: 1
Exten: 31337
Context: inbound

)

    Asterisk::Event.from(raw).message["Event"].should eq "Newchannel"
    Asterisk::Event.from(raw).message["Context"].should eq "inbound"
  end

  it "encode action" do
    action = Asterisk::Action.new(
      "Login", UUID.v4.hexstring,
      Hash{
        "Username" => "test",
        "AuthType" => "plain",
        "Secret"   => "test",
        "Events"   => "on",
      },
      variables: Hash{"demo" => "demo"}
    )

    action.as_s.should contain("Action: Login")
    action.as_s.should contain("Secret: test")
    action.as_s.should contain("Variable: demo=demo")
    action.as_s.should contain("\n\n")
  end
end
