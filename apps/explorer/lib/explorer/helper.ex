defmodule Explorer.Helper do
  @moduledoc """
  Auxiliary common functions.
  """

  alias ABI.TypeDecoder
  alias Explorer.Chain
  alias Explorer.Chain.{Data, Hash}

  import Ecto.Query, only: [where: 3]
  import Explorer.Chain.SmartContract, only: [burn_address_hash_string: 0]

  @max_safe_integer round(:math.pow(2, 63)) - 1

  @spec decode_data(binary() | map(), list()) :: list() | nil
  def decode_data("0x", types) do
    for _ <- types, do: nil
  end

  def decode_data("0x" <> encoded_data, types) do
    decode_data(encoded_data, types)
  end

  def decode_data(%Data{} = data, types) do
    data
    |> Data.to_string()
    |> decode_data(types)
  end

  def decode_data(encoded_data, types) do
    encoded_data
    |> Base.decode16!(case: :mixed)
    |> TypeDecoder.decode_raw(types)
  end

  @doc """
  Takes an Ethereum hash and converts it to a standard 20-byte address by
  truncating the leading zeroes. If the input is `nil`, it returns the burn
  address.

  ## Parameters
  - `address_hash` (`EthereumJSONRPC.hash()` | `nil`): The full address hash to
    be truncated, or `nil`.

  ## Returns
  - `EthereumJSONRPC.address()`: The truncated address or the burn address if
    the input is `nil`.

  ## Examples

      iex> truncate_address_hash("0x000000000000000000000000abcdef1234567890abcdef1234567890abcdef")
      "0xabcdef1234567890abcdef1234567890abcdef"

      iex> truncate_address_hash(nil)
      "0x0000000000000000000000000000000000000000"
  """
  @spec truncate_address_hash(EthereumJSONRPC.hash() | nil) :: EthereumJSONRPC.address()
  def truncate_address_hash(address_hash)

  def truncate_address_hash(nil), do: burn_address_hash_string()

  def truncate_address_hash("0x000000000000000000000000" <> truncated_hash) do
    "0x#{truncated_hash}"
  end

  @doc """
    Safely parses a string or integer into an integer value.

    Handles both string and integer inputs:
    - For string input: Converts only if the entire string represents a valid integer
    - For integer input: Returns the integer as is
    - For any other input: Returns nil

    ## Parameters
    - `int_or_string`: A binary string containing an integer or an integer value

    ## Returns
    - The parsed integer if successful
    - `nil` if the input is invalid or contains non-integer characters
  """
  @spec parse_integer(binary() | integer()) :: integer() | nil
  def parse_integer(int_or_string)

  def parse_integer(integer_string) when is_binary(integer_string) do
    case Integer.parse(integer_string) do
      {integer, ""} -> integer
      _ -> nil
    end
  end

  def parse_integer(value) when is_integer(value) do
    value
  end

  def parse_integer(_integer_string), do: nil

  @doc """
  Parses number from hex string or decimal number string
  """
  @spec parse_number(binary() | nil) :: integer() | nil
  def parse_number(nil), do: nil

  def parse_number(number) when is_integer(number) do
    number
  end

  def parse_number("0x" <> hex_number) do
    {number, ""} = Integer.parse(hex_number, 16)

    number
  end

  def parse_number(""), do: 0

  def parse_number(string_number) do
    {number, ""} = Integer.parse(string_number, 10)

    number
  end

  @doc """
    Converts a string to an integer, ensuring it's non-negative and within the
    acceptable range for database insertion.

    ## Examples

        iex> safe_parse_non_negative_integer("0")
        {:ok, 0}

        iex> safe_parse_non_negative_integer("-1")
        {:error, :negative_integer}

        iex> safe_parse_non_negative_integer("27606393966689717254124294199939478533331961967491413693980084341759630764504")
        {:error, :too_big_integer}
  """
  def safe_parse_non_negative_integer(string) do
    case Integer.parse(string) do
      {num, ""} ->
        case num do
          _ when num > @max_safe_integer -> {:error, :too_big_integer}
          _ when num < 0 -> {:error, :negative_integer}
          _ -> {:ok, num}
        end

      _ ->
        {:error, :invalid_integer}
    end
  end

  @doc """
    Function to preload a `struct` for each element of the `list`.
    You should specify a primary key for a `struct` in `references_field`,
    and the list element's foreign key in `foreign_key_field`.
    Results will be placed to `preload_field`
  """
  @spec custom_preload(list(map()), keyword(), atom(), atom(), atom(), atom()) :: list()
  def custom_preload(list, options, struct, foreign_key_field, references_field, preload_field) do
    to_fetch_from_db = list |> Enum.map(& &1[foreign_key_field]) |> Enum.uniq()

    associated_elements =
      struct
      |> where([t], field(t, ^references_field) in ^to_fetch_from_db)
      |> Chain.select_repo(options).all()
      |> Enum.reduce(%{}, fn el, acc -> Map.put(acc, Map.from_struct(el)[references_field], el) end)

    Enum.map(list, fn el -> Map.put(el, preload_field, associated_elements[el[foreign_key_field]]) end)
  end

  @doc """
  Decode json
  """
  @spec decode_json(any()) :: map() | list() | nil
  def decode_json(data, nft? \\ false)

  def decode_json(nil, _), do: nil

  def decode_json(data, nft?) do
    if String.valid?(data) do
      safe_decode_json(data, nft?)
    else
      data
      |> :unicode.characters_to_binary(:latin1)
      |> safe_decode_json(nft?)
    end
  end

  defp safe_decode_json(data, nft?) do
    case Jason.decode(data) do
      {:ok, decoded} -> decoded
      _ -> if nft?, do: {:error, data}, else: %{error: data}
    end
  end

  @doc """
  Checks if input is a valid URL
  """
  @spec validate_url(String.t() | nil) :: {:ok, String.t()} | :error
  def validate_url(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{host: nil} -> :error
      _ -> {:ok, url}
    end
  end

  def validate_url(_), do: :error

  @doc """
    Validate url
  """
  @spec valid_url?(String.t()) :: boolean()
  def valid_url?(string) when is_binary(string) do
    uri = URI.parse(string)

    !is_nil(uri.scheme) && !is_nil(uri.host)
  end

  def valid_url?(_), do: false

  @doc """
  Compare two values and returns either :lt, :eq or :gt.

  Please be careful: this function compares arguments using `<` and `>`,
  hence it should not be used to compare structures (for instance %DateTime{} or %Decimal{}).
  """
  @spec compare(term(), term()) :: :lt | :eq | :gt
  def compare(a, b) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  @doc """
  Conditionally hides scam addresses in the given query.

  ## Parameters

    - query: The Ecto query to be modified.
    - address_hash_key: The key used to identify address hash field in the query to join with base query table on.

  ## Returns

  The modified query with scam addresses hidden, if applicable.
  """
  @spec maybe_hide_scam_addresses(nil | Ecto.Query.t(), atom(), [
          Chain.paging_options() | Chain.api?() | Chain.show_scam_tokens?()
        ]) :: Ecto.Query.t()
  def maybe_hide_scam_addresses(nil, _address_hash_key, _options), do: nil

  def maybe_hide_scam_addresses(query, address_hash_key, options) do
    if Application.get_env(:block_scout_web, :hide_scam_addresses) && !options[:show_scam_tokens?] do
      query
      |> where(
        [q],
        fragment(
          "NOT EXISTS (SELECT 1 FROM scam_address_badge_mappings sabm WHERE sabm.address_hash=?)",
          field(q, ^address_hash_key)
        )
      )
    else
      query
    end
  end

  @doc """
  Checks if a specified time interval has passed since a given datetime.

  This function compares the given datetime plus the interval against the current
  time. It returns `true` if the interval has passed, or the number of seconds
  remaining if it hasn't.

  ## Parameters
  - `sent_at`: The reference datetime, or `nil`.
  - `interval`: The time interval in milliseconds.

  ## Returns
  - `true` if the interval has passed or if `sent_at` is `nil`.
  - An integer representing the number of seconds remaining in the interval if it
    hasn't passed yet.
  """
  @spec check_time_interval(DateTime.t() | nil, integer()) :: true | integer()
  def check_time_interval(nil, _interval), do: true

  def check_time_interval(sent_at, interval) do
    now = DateTime.utc_now()

    if sent_at
       |> DateTime.add(interval, :millisecond)
       |> DateTime.compare(now) != :gt do
      true
    else
      sent_at
      |> DateTime.add(interval, :millisecond)
      |> DateTime.diff(now, :second)
    end
  end

  @doc """
  Retrieves the host URL for the BlockScoutWeb application.

  This function fetches the host URL from the application's configuration,
  specifically from the `:block_scout_web` application's `BlockScoutWeb.Endpoint`
  configuration.

  ## Returns
  A string containing the host URL for the BlockScoutWeb application.
  """
  @spec get_app_host :: String.t()
  def get_app_host do
    Application.get_env(:block_scout_web, BlockScoutWeb.Endpoint)[:url][:host]
  end

  @doc """
  Converts `Explorer.Chain.Hash.t()` or string hash to DB-acceptable format.
  For example "0xabcdef1234567890abcdef1234567890abcdef" -> "\\xabcdef1234567890abcdef1234567890abcdef"
  """
  @spec hash_to_query_string(Hash.t() | String.t()) :: String.t()
  def hash_to_query_string(hash) do
    s_hash =
      hash
      |> to_string()
      |> String.trim_leading("0")

    "\\#{s_hash}"
  end

  def parse_boolean("true"), do: true
  def parse_boolean("false"), do: false

  def parse_boolean(true), do: true
  def parse_boolean(false), do: false

  def parse_boolean(_), do: false

  @doc """
  Adds 0x at the beginning of the binary hash, if it is not already there.
  """
  @spec add_0x_prefix(input) :: output
        when input: nil | :error | binary() | Hash.t() | [input],
             output: nil | :error | binary() | [output]
  def add_0x_prefix(nil), do: nil

  def add_0x_prefix(:error), do: :error

  def add_0x_prefix(binary_hashes) when is_list(binary_hashes) do
    binary_hashes
    |> Enum.map(fn binary_hash -> add_0x_prefix(binary_hash) end)
  end

  def add_0x_prefix(%Hash{bytes: bytes}) do
    "0x" <> Base.encode16(bytes, case: :lower)
  end

  def add_0x_prefix(binary_hash) when is_binary(binary_hash) do
    if String.starts_with?(binary_hash, "0x") do
      binary_hash
    else
      "0x" <> Base.encode16(binary_hash, case: :lower)
    end
  end
end
