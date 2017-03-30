[void][reflection.assembly]::LoadWithPartialName("System.Windows.Forms")

$class_definition = @"

using System;
using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

public class DrawPane : Control
{
    public DrawPane()
    {
        InitializeComponent();

        this.SetStyle(
            ControlStyles.UserPaint |
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.DoubleBuffer, true);
		
		this.Width = 800
		this.Height = 600
		
    }

	protected void draw_elipse(PaintEventArgs e)
	{
		Pen pen = new Pen(Color.Aquamarine,2);
		SolidBrush brush = new SolidBrush(Color.Aquamarine);
	
		e.DrawEllipse(pen, 10, 10, 100, 20);
		e.FillEllipse(brush, 10, 50, 100, 20);
	}
    protected override void OnPaint(PaintEventArgs pe)
    {
        // we draw the progressbar normally 
        // with the flags sets to our settings
        draw_elipse(pe.Graphics);
    }
}	
	

"@


Add-Type -TypeDefinition $class_definition -Language CSharp 
Remove-Variable class_definition




[System.Windows.Forms.Application]::EnableVisualStyles()
$form = new-object Windows.Forms.Form
$form.Text = "Image Viewer"

$surface = new-object DrawPane
$form.controls.add($surface)
$form.ShowDialog()

























