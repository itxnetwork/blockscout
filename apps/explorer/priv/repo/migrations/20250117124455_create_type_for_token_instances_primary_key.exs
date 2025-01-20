defmodule Explorer.Repo.Migrations.CreateTypeForTokenInstancesPrimaryKey do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TYPE token_instance_id AS (
      token_id numeric(78,0),
      token_contract_address_hash bytea
    );
    """)
  end

  def down do
    execute("""
    DROP TYPE token_instance_id;
    """)
  end
end
