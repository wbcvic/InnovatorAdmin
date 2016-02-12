﻿using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;

namespace Innovator.Client
{
  public class SubSelect : IEnumerable<SubSelect>
  {
    private string _name;
    private List<SubSelect> _children;

    public int Count
    {
      get
      {
        if (_children == null) return 0;
        return _children.Count;
      }
    }
    public string Name
    {
      get { return _name; }
    }
    public SubSelect this[int index]
    {
      get
      {
        if (_children == null) throw new IndexOutOfRangeException();
        return _children[index];
      }
    }

    public SubSelect() { }
    public SubSelect(string name)
    {
      _name = name;
    }
    internal SubSelect(string name, IEnumerable<SubSelect> children)
    {
      _name = name;
      _children = children.ToList();
    }
    internal SubSelect(IEnumerable<SubSelect> children)
    {
      _children = children.ToList();
    }

    public void Add(SubSelect child)
    {
      if (child == null) return;
      if (_children == null) _children = new List<SubSelect>();
      _children.Add(child);
    }
    public void EnsurePath(params string[] path)
    {
      EnsurePath((IEnumerable<string>)path);
    }
    public void EnsurePath(IEnumerable<string> path)
    {
      if (!path.Any()) return;
      if (_children == null) _children = new List<SubSelect>();
      var name = path.First();
      var match = _children.FirstOrDefault(c => c.Name == name);
      if (match == null)
      {
        match = (SubSelect)name;
        _children.Add(match);
      }
      match.EnsurePath(path.Skip(1));
    }

    public IEnumerator<SubSelect> GetEnumerator()
    {
      if (_children == null) return Enumerable.Empty<SubSelect>().GetEnumerator();
      return _children.GetEnumerator();
    }

    public void Sort()
    {
      if (_children != null)
      {
        _children.Sort((x, y) => (x.Name ?? "").CompareTo(y.Name ?? ""));
        foreach (var child in _children)
        {
          child.Sort();
        }
      }
    }

    System.Collections.IEnumerator System.Collections.IEnumerable.GetEnumerator()
    {
      return this.GetEnumerator();
    }

    public static implicit operator SubSelect(string select)
    {
      return FromString(select);
    }

    public override string ToString()
    {
      return Write(new StringBuilder()).ToString();
    }

    private StringBuilder Write(StringBuilder builder)
    {
      if (string.IsNullOrEmpty(_name))
      {
        builder.EnsureCapacity(_children.Count * 5);
        Write(builder, _children);
      }
      else
      {
        builder.Append(_name);
        if (_children != null)
        {
          builder.Append('(');
          builder.EnsureCapacity(_children.Count * 5);
          Write(builder, _children);
          builder.Append(')');
        }
      }
      return builder;
    }

    public static string ToString(IEnumerable<SubSelect> items)
    {
      return Write(new StringBuilder(), items).ToString();
    }

    public static SubSelect FromString(string select)
    {
      var result = new SubSelect();
      if (string.IsNullOrEmpty(select))
        return result;

      var path = new Stack<SubSelect>();
      path.Push(result);
      var start = 0;
      for (var i = 0; i < select.Length; i++)
      {
        switch (select[i])
        {
          case ',':
            if (i - start > 0)
              path.Peek().Add(new SubSelect(select.Substring(start, i - start).Trim()));
            start = i + 1;
            break;
          case '(':
            if (i - start > 0)
            {
              var curr = new SubSelect(select.Substring(start, i - start).Trim());
              path.Peek().Add(curr);
              path.Push(curr);
            }
            start = i + 1;
            break;
          case ')':
            if (i - start > 0)
              path.Peek().Add(new SubSelect(select.Substring(start, i - start).Trim()));
            path.Pop();
            start = i + 1;
            break;
        }
      }

      if (start < select.Length)
      {
        result.Add(new SubSelect(select.Substring(0, select.Length - start).Trim()));
      }
      return result;
    }

    private static StringBuilder Write(StringBuilder builder, IEnumerable<SubSelect> items)
    {
      var first = true;
      foreach (var item in items)
      {
        if (!first) builder.Append(',');
        item.Write(builder);
        first = false;
      }
      return builder;
    }
  }
}
