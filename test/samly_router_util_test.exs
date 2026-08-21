defmodule SamlyRouterUtilTest do
  use ExUnit.Case, async: true
  use Plug.Test

  alias Samly.RouterUtil

  # The URL handed to redirect/3 is already fully percent-encoded: for SAML
  # redirects :esaml_binding.encode_http_redirect builds the query with
  # uri_string:compose_query, which encodes every reserved character. Wrapping
  # the destination in URI.encode/1 here re-encodes each % as %25 and corrupts
  # the SAMLRequest/RelayState parameters at the IdP. That double encoding was
  # a real bug, removed upstream in v1.4.0 ("remove uri double encoding") -
  # these tests pin the fix so it is not reintroduced.
  describe "redirect/3" do
    @encoded_dest "https://idp.example.com/sso?SAMLRequest=nZFBa8%2BJwb&RelayState=https%3A%2F%2Fsp.example.com%2Fapp"

    test "passes an already-encoded location through byte-identical" do
      conn = conn(:get, "/") |> RouterUtil.redirect(302, @encoded_dest)

      assert [location] = Plug.Conn.get_resp_header(conn, "location")
      assert location == @encoded_dest
      refute location =~ "%25"
    end

    test "sets the status code and halts" do
      conn = conn(:get, "/") |> RouterUtil.redirect(302, @encoded_dest)

      assert conn.status == 302
      assert conn.halted
    end
  end

  describe "send_saml_request/5 via HTTP-Redirect binding" do
    test "RelayState with reserved characters roundtrips through the location URL" do
      relay_state = "https://sp.example.com/return?a=b&c=d"

      {idp_signin_url, req_xml_frag} = gen_signin_req()

      conn =
        conn(:get, "/")
        |> RouterUtil.send_saml_request(idp_signin_url, true, req_xml_frag, relay_state)

      assert conn.status == 302
      assert [location] = Plug.Conn.get_resp_header(conn, "location")

      # A reintroduced URI.encode would turn each % into %25, so the decoded
      # RelayState would come back still-encoded and this roundtrip would fail.
      query = URI.parse(location).query
      assert %{"RelayState" => ^relay_state, "SAMLRequest" => _} = URI.decode_query(query)
      refute location =~ "%25"
    end
  end

  defp gen_signin_req do
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
    idp_data = Samly.IdpData.load_provider(idp_config, %{sp_data.id => sp_data})

    Samly.Helper.gen_idp_signin_req(
      idp_data.esaml_sp_rec,
      idp_data.esaml_idp_rec,
      idp_data.nameid_format
    )
  end
end
