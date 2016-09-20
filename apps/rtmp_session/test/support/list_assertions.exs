defmodule ListAssertions.AssertionError do
  defexception expression: nil,
               list: nil,
               message: nil

  def message(exception) do
    "No entries in the list matched the requested expression:\n\n"  
      <> "list: #{inspect(exception.list)} \n\n"
      <> "expression: #{exception.expression}\n"
  end  
end

defmodule ListAssertions do
  defmacro __using__(_options) do
    quote do
      import ListAssertions
    end
  end

  defmacro assert_contains(list, match_expression) do
    string_representation = Macro.to_string(match_expression)

    quote do
      case Enum.find(unquote(list), nil, &match?(unquote(match_expression), &1)) do
        nil ->
          raise(ListAssertions.AssertionError, 
            list: unquote(list),
            expression: unquote(string_representation),
            message: "No entries matched the passed in expression")

        item -> item
      end
    end
  end
end