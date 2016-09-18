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

      defp __assert_list_contains([], _fun, expression_as_string, full_list) do
        raise(ListAssertions.AssertionError, 
          list: full_list,
          expression: expression_as_string,
          message: "No entries matched the passed in expression")
      end

      defp __assert_list_contains([head | tail], test_fun, expression_as_string, full_list) do
        case test_fun.(head) do
          {:ok, item} -> item
          nil -> __assert_list_contains(tail, test_fun, expression_as_string, full_list)
        end
      end
    end
  end

  defmacro assert_contains(list, match_expression) do
    string_representation = Macro.to_string(match_expression)

    test_fun = quote do
      fn(item) -> 
        case item do
          unquote(match_expression) -> {:ok, item}
          _ -> nil
        end
      end
    end 

    quote do
      __assert_list_contains(
        unquote(list), 
        unquote(test_fun), 
        unquote(string_representation),
        unquote(list))
    end
  end
end