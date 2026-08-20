defmodule SamlyHelperTest do
  use ExUnit.Case

  alias Samly.Helper

  @valid_xml ~s(<samlp:Response xmlns:samlp="urn:oasis:names:tc:SAML:2.0:protocol"/>)

  describe "SAML payload decoding of malformed payloads" do
    test "base64 that is not XML" do
      assert {:error, {:invalid_response, _}} = decode(Base.encode64("not-xml-at-all"))
    end

    test "XML with mismatched tags" do
      assert {:error, {:invalid_response, _}} = decode(Base.encode64("<a><b></a>"))
    end

    test "XML with a truncated CDATA section" do
      assert {:error, {:invalid_response, _}} = decode(Base.encode64("<a><![CDATA[truncated"))
    end

    test "XML with an entity declaration" do
      xxe =
        ~s(<?xml version="1.0"?><!DOCTYPE foo [<!ENTITY xxe SYSTEM "file:///etc/passwd">]><foo>&xxe;</foo>)

      assert {:error, {:invalid_response, _}} = decode(Base.encode64(xxe))
    end

    test "payload that is not valid base64" do
      assert {:error, {:invalid_response, _}} = decode("%%%not-base64%%%")
    end

    test "deflated garbage" do
      assert {:error, {:invalid_response, _}} = decode(Base.encode64(:zlib.zip("garbage")))
    end
  end

  describe "SAML payload decoding of well-formed payloads" do
    # A decode failure returns {:error, {:invalid_response, _}}; a decode that
    # succeeds reaches :esaml_sp.validate_assertion, which rejects this
    # assertion-less Response with a different error. Distinguishing the two is
    # what pins the decode step - and, for the deflated case, the fork's
    # SAMLEncoding-ignoring deflate auto-detect.
    test "plain base64 XML decodes and reaches assertion validation" do
      assert {:error, reason} = auth_resp(Base.encode64(@valid_xml))
      refute match?({:invalid_response, _}, reason)
    end

    test "deflated base64 XML decodes regardless of the SAMLEncoding param" do
      assert {:error, reason} = auth_resp(Base.encode64(:zlib.zip(@valid_xml)))
      refute match?({:invalid_response, _}, reason)
    end
  end

  # The decode fails before the sp argument is used, so nil suffices.
  defp decode(payload), do: Helper.decode_idp_auth_resp(nil, nil, payload)

  defp auth_resp(payload), do: Helper.decode_idp_auth_resp(sp_rec(), nil, payload)

  defp sp_rec do
    sp_config = %{
      id: "sp1",
      entity_id: "urn:test:sp1",
      certfile: "test/data/test.crt",
      keyfile: "test/data/test.pem"
    }

    idp_config = %{
      id: "idp1",
      sp_id: "sp1",
      base_url: "http://samly.howto:4003/sso",
      metadata_file: "test/data/idp_metadata.xml"
    }

    sp_data = Samly.SpData.load_provider(sp_config)
    Samly.IdpData.load_provider(idp_config, %{sp_data.id => sp_data}).esaml_sp_rec
  end
end
