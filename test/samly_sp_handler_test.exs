defmodule SamlySpHandlerTest do
  use ExUnit.Case

  alias Samly.{IdpData, SpData}

  @sp_config %{
    id: "sp1",
    entity_id: "urn:test:sp1",
    certfile: "test/data/test.crt",
    keyfile: "test/data/test.pem"
  }

  @idp_config %{
    id: "idp1",
    sp_id: "sp1",
    base_url: "http://samly.howto:4003/sso",
    metadata_file: "test/data/idp_metadata.xml",
    debug_mode: true
  }

  setup do
    sp_data = SpData.load_provider(@sp_config)
    idp_data = IdpData.load_provider(@idp_config, %{sp_data.id => sp_data})

    Application.put_env(:samly, :idp_id_from, :path_segment)
    Application.put_env(:samly, :identity_providers, %{idp_data.id => idp_data})

    on_exit(fn ->
      Application.delete_env(:samly, :idp_id_from)
      Application.delete_env(:samly, :identity_providers)
    end)

    :ok
  end

  test "debug mode escapes the attacker-controlled payload in the error response" do
    conn =
      Plug.Test.conn(:post, "/sp/consume/idp1", %{"SAMLResponse" => "<script>alert(1)</script>"})
      |> Plug.Test.init_test_session(%{})
      |> Samly.Router.call([])

    assert conn.status == 403
    refute conn.resp_body =~ "<script>"
    assert conn.resp_body =~ "&lt;script&gt;"
  end
end
