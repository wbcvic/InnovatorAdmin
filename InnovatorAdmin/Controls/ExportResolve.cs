﻿using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Drawing;
using System.Data;
using System.Linq;
using System.Text;
using System.Windows.Forms;
using System.Xml;

namespace Aras.Tools.InnovatorAdmin.Controls
{
  public partial class ExportResolve : UserControl, IWizardStep
  {
    private IWizard _wizard;
    private BindingList<ImportStepResolve> _items;
    private bool _changes = false;

    public ExportResolve()
    {
      InitializeComponent();
      resolveGrid.AutoGenerateColumns = false;
    }

    public void Configure(IWizard wizard)
    {
      _wizard = wizard;
      _wizard.NextEnabled = true;
      _wizard.Message = "Please review the install script and modify as necessary";
      _items = new BindingList<ImportStepResolve>(_wizard.InstallScript.Lines.Select(i => new ImportStepResolve() { Item = i }).ToList());
      resolveGrid.DataSource = _items;
    }

    public void GoNext()
    {
      if (_items.Any(i => i.HasChanges))
      {
        var prog = new ProgressStep<ExportProcessor>(_wizard.ExportProcessor);
        prog.MethodInvoke = e => {
          _wizard.InstallScript.Lines = (from i in _items
                                         where !i.HasChanges
                                         select i.Item).ToList();
          e.Export(_wizard.InstallScript, 
            e.NormalizeRequest(from i in _items
                               where i.HasChanges
                               select i.Item.Reference));
        };
        prog.GoNextAction = () => _wizard.GoToStep(new ExportResolve());
        _wizard.GoToStep(prog);
      }
      else
      {
        if (_changes)
        {
          _wizard.InstallScript.Lines = _items.Select(i => i.Item).ToList();
        }

        _wizard.GoToStep(new ExportOptions());
      }
    }

    private class ImportStepResolve
    {
      private InstallItem _item;
      private InstallType _type;

      public InstallItem Item 
      {
        get { return _item; }
        set 
        { 
          _item = value;
          _type = _item.Type;
        }
      }
      public string Name
      {
        get { return this.Item.Name; }
      }
      public string Origin
      {
        get { return (this.Item.Reference.Origin == null ? "" : this.Item.Reference.Origin.ToString()); }
      }
      public InstallType Type
      {
        get { return _type; }
        set { _type = value; }
      }
      public bool HasChanges
      {
        get { return _type != _item.Type; }
      }

      public void Reset()
      {
        _type = _item.Type;
      }
    }
    
    private void resolveGrid_CellMouseClick(object sender, DataGridViewCellMouseEventArgs e)
    {
      try
      {
        if (e.Button == System.Windows.Forms.MouseButtons.Right && e.RowIndex >= 0 && e.ColumnIndex >= 0)
        {
          if (!resolveGrid[e.ColumnIndex, e.RowIndex].Selected)
          {
            resolveGrid.ClearSelection();
            resolveGrid.Rows[e.RowIndex].Selected = true;
          }

          var items = resolveGrid.SelectedRows.OfType<DataGridViewRow>().Select(r => (ImportStepResolve)r.DataBoundItem).ToList();
          var showList = items.All(i => i.Type == InstallType.DependencyCheck || i.Type == InstallType.Warning || i.HasChanges);

          mniIncludeInPackage.Enabled = showList;
          mniReset.Enabled = showList;
          conStrip.Show(Cursor.Position);
        }
      }
      catch (Exception ex)
      {
        Utils.HandleError(ex);
      }
    }

    private void mniIncludeInPackage_Click(object sender, EventArgs e)
    {
      try
      {
        foreach (var item in SelectedRows())
        {
          item.Type = InstallType.Create;
        }
        UpdateUi();
      }
      catch (Exception ex)
      {
        Utils.HandleError(ex);
      }
    }

    private void mniReset_Click(object sender, EventArgs e)
    {
      try
      {
        foreach (var item in SelectedRows())
        {
          item.Reset();
        }
        UpdateUi();
      }
      catch (Exception ex)
      {
        Utils.HandleError(ex);
      }
    }

    private void UpdateUi()
    {
      resolveGrid.InvalidateColumn(colType.Index);
      _wizard.NextLabel = (_items.Any(i => i.HasChanges) ? "Rescan" : "Next");
    }

    private void mniEdit_Click(object sender, EventArgs e)
    {
      using (var dialog = new Editor())
      {
        dialog.AllowRun = false;
        dialog.AmlGetter = o => FormatXml(((ImportStepResolve)o).Item.Script);
        dialog.AmlSetter = (o,a) => ((ImportStepResolve)o).Item.SetScript(a);
        dialog.DisplayMember = "Name";
        dialog.DataSource = SelectedRows().ToList();
        dialog.SetConnection(_wizard.Innovator, _wizard.ConnectionInfo.First().ConnectionName);
        dialog.ShowDialog(this);
      }
    }

    private string FormatXml(XmlNode node)
    {
      var settings = new XmlWriterSettings();
      settings.OmitXmlDeclaration = true;
      settings.Indent = true;
      settings.IndentChars = "  ";

      using (var writer = new System.IO.StringWriter())
      {
        using (var xml = XmlTextWriter.Create(writer, settings))
        {
          node.WriteTo(xml);
        }
        return writer.ToString();
      }
    }

    private IEnumerable<ImportStepResolve> SelectedRows()
    {
      return resolveGrid.SelectedRows.OfType<DataGridViewRow>().OrderBy(r => r.Index).Select(r => (ImportStepResolve)r.DataBoundItem);
    }

    private void resolveGrid_CellFormatting(object sender, DataGridViewCellFormattingEventArgs e)
    {
      try
      {
        if (e.RowIndex >= 0 && e.ColumnIndex >= 0)
        {
          var line = (ImportStepResolve)resolveGrid.Rows[e.RowIndex].DataBoundItem;
          if (line.Item.Type == InstallType.DependencyCheck || line.Item.Type == InstallType.Warning)
          {
            e.CellStyle.BackColor = Color.LightYellow;
          }
        }
      }
      catch (Exception ex)
      {
        Utils.HandleError(ex);
      }
    }

    private void mniRemoveReferencingItems_Click(object sender, EventArgs e)
    {
      try
      {
        foreach (var item in SelectedRows().ToList())
        {
          _items.Remove(item);
          _wizard.ExportProcessor.RemoveReferencingItems(_wizard.InstallScript, item.Item.Reference);
          _changes = true;
        }
        UpdateUi();
      }
      catch (Exception ex)
      {
        Utils.HandleError(ex);
      }
    }

    private void mniRemoveReferences_Click(object sender, EventArgs e)
    {
      try
      {
        foreach (var item in SelectedRows().ToList())
        {
          _items.Remove(item);
          _wizard.ExportProcessor.RemoveReferences(_wizard.InstallScript, item.Item.Reference);
          _changes = true;
        }
        UpdateUi();
      }
      catch (Exception ex)
      {
        Utils.HandleError(ex);
      }
    }
  }
}
