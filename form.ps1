[void][reflection.assembly]::LoadWithPartialName("System.Windows.Forms")

$class_definition = @"

using System;
//using System.Collections.Generic;
using System.Drawing;
using System.Windows.Forms;

public class DrawPane : Form
{
	public int px;
	public int py;
	public int vx;
	public int vy;
	
    public DrawPane()
    {
        //InitializeComponent();

        this.SetStyle(
            ControlStyles.UserPaint |
            ControlStyles.AllPaintingInWmPaint |
            ControlStyles.DoubleBuffer, true);
		
		this.KeyDown += new KeyDownEventHandler(H_KeyDown);
		this.Width = 800;
		this.Height = 600;
		
		this.px = this.Width / 2;
		this.py = this.Height / 2;
		this.vx = 5;
		this.vy = 5;
		
    }
	
	void H_KeyDown(object sender, KeyEventArgs e)
	{
		switch (e.KeyCode)
		{
			case Keys.Up:
				this.py += vy;
				break;
			case Keys.Down:
				this.py -= vy;
				break;
			case Keys.Right:
				this.px += vx;
				break;
			case Keys.Left:
				this.px -= vx;
				break;
		}
		e.Handled = true;
	}

	protected void update(int x, int y)
	{
		this.px = x;
		this.py = y;
		
	}

	protected void draw_elipse(PaintEventArgs e)
	{
		SolidBrush brush = new SolidBrush(Color.Blue);
		e.Graphics.FillEllipse(brush, this.px, this.py, 50, 50);
	}
	
    protected override void OnPaint(PaintEventArgs pe)
    {
        // we draw the progressbar normally 
        // with the flags sets to our settings
        draw_elipse(pe);
    }
}	
	

"@

$assem = @(
	"System",
	#"System.Collections.Generic",
	"System.Drawing",
	"System.Windows.Forms"
	)

Add-Type -ReferencedAssemblies $assem -TypeDefinition $class_definition -Language CSharp 
Remove-Variable class_definition




[System.Windows.Forms.Application]::EnableVisualStyles()
#$form = new-object Windows.Forms.Form

$surface = new-object DrawPane
$surface.Text = "Image Viewer"
#$form.controls.add($surface)

$surface.ShowDialog()

























